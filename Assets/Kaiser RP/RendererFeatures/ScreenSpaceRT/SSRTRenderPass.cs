using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSRTRenderPass : ScriptableRenderPass
{
    private SSRTSettings settings; //基本参数
    private Material material; //材质
    private int frameIndex;

    private static class SSR_InputIDs
    {
        public static int SceneColor = Shader.PropertyToID("_SSR_SceneColor_RT");
        public static int PyramidDepth = Shader.PropertyToID("_PyramidDepth");
    }

    private static class SSR_OutputIDs
    {
        public static int UVWPdf = Shader.PropertyToID("_SSR_Out_UVWPdf");
        public static int ColorMask = Shader.PropertyToID("_SSR_Out_ColorMask");
        public static int SpatialFilter = Shader.PropertyToID("_SSR_Out_SpatialFilter");
        public static int TemporalPrevTexture = Shader.PropertyToID("_SSR_Temporal_PrevTexture");
        public static int TemporalCurrTexture = Shader.PropertyToID("_SSR_Temporal_CurrTexture");
        public static int Combine = Shader.PropertyToID("_SSR_Out_Combine");
    }

    private static class SSR_Matrix
    {
        public static Matrix4x4 Proj;
        public static Matrix4x4 InvProj;
        public static Matrix4x4 InvViewProj;
        public static Matrix4x4 viewProj;
        public static Matrix4x4 prevViewProj;
    }

    public SSRTRenderPass(SSRTSettings settings)
    {
        this.settings = settings;

        if (settings.debugMode != SSRTSettings.DebugMode.None)
        {
            this.renderPassEvent = RenderPassEvent.AfterRendering;
        }
        else
        {
            this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机
        }
        profilingSampler = new ProfilingSampler("[Kaiser] ScreenSpaceRT");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

        if (material == null && settings.shader != null)
        {
            material = CoreUtils.CreateEngineMaterial(settings.shader);
        }
    }
    void UpdateCurrentFrameIndex()
    {
        frameIndex = (frameIndex + 1) % 8;
    }

    void UpdateTransformMatrix(Camera camera)
    {
        SSR_Matrix.Proj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
        SSR_Matrix.InvProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSR_Matrix.InvViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSR_Matrix.viewProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false) * camera.worldToCameraMatrix;
    }

    void UpdatePreviousTransformMatrix(Camera camera)
    {
        SSR_Matrix.prevViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
    }

    void UpdateRenderTextures(CommandBuffer cmd, int width, int height)
    {
        RenderTextureDescriptor descriptorDefault = new RenderTextureDescriptor(
                    width, height, RenderTextureFormat.Default, 0, 0);
        descriptorDefault.sRGB = false;
        descriptorDefault.enableRandomWrite = true;

        RenderTextureDescriptor descriptorR8 = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.R8, 0, 0);
        descriptorR8.sRGB = false;
        descriptorR8.enableRandomWrite = true;

        cmd.GetTemporaryRT(SSR_InputIDs.SceneColor, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.UVWPdf, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.ColorMask, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.SpatialFilter, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.Combine, descriptorDefault);

    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        UpdateCurrentFrameIndex();

        var cmd = CommandBufferPool.Get();

        int k1 = settings.computeShader.FindKernel("SSR_RayTracing");
        int k2 = settings.computeShader.FindKernel("SSR_SpatialFilter");
        int k4 = settings.computeShader.FindKernel("SSR_Combine");

        using (new ProfilingScope(cmd, profilingSampler))
        {
            UpdateTransformMatrix(renderingData.cameraData.camera);

            // Prepare
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;

            #region Update RenderTextures
            {
                UpdateRenderTextures(cmd, width, height);
            }
            #endregion

            cmd.BeginSample("Ray Tracing");
            {
                // Init Common Settings
                cmd.SetComputeVectorParam(settings.computeShader, "_SSR_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
                cmd.SetComputeIntParam(settings.computeShader, "_SSR_FrameIndex", frameIndex);
                cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Thickness", settings.SSR_Thickness);
                cmd.SetComputeFloatParam(settings.computeShader, "_SSR_ScreenFade", settings.SSR_ScreenFade);

                // Init Matrix
                cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_ProjMatrix", SSR_Matrix.Proj);
                cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_InvProjMatrix", SSR_Matrix.InvProj);
                cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_InvViewProjMatrix", SSR_Matrix.InvViewProj);

                // Init Hiz Trace Settings
                cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
                cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
                cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
                cmd.SetComputeIntParam(settings.computeShader, "_Hiz_RaySteps", settings.Hiz_RaySteps);

                // Init Input Texture

                cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), SSR_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_SceneColor_RT", SSR_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_PyramidDepth_RT", SSR_InputIDs.PyramidDepth);

                // Init Output Texture
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_UVWPdf", SSR_OutputIDs.UVWPdf);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_ColorMask", SSR_OutputIDs.ColorMask);

                // Dispatch
                cmd.DispatchCompute(settings.computeShader, k1, width / 8, height / 8, 1);

                // Release
                // cmd.ReleaseTemporaryRT(SSR_InputIDs.SceneColor);
            }
            cmd.EndSample("Ray Tracing");

            cmd.BeginSample("Spatial Filter");
            {
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_UVWPdf", SSR_OutputIDs.UVWPdf);
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_ColorMask", SSR_OutputIDs.ColorMask);


                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Out_SpatialFilter", SSR_OutputIDs.SpatialFilter);
                cmd.DispatchCompute(settings.computeShader, k2, width / 8, height / 8, 1);
            }
            cmd.EndSample("Spatial Filter");

            cmd.BeginSample("Temporal Filter");
            {
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Temporal_PrevTexture", SSR_OutputIDs.TemporalPrevTexture); // TODO:
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Temporal_CurrTexture", SSR_OutputIDs.SpatialFilter);



            }
            cmd.EndSample("Temporal Filter");

            cmd.BeginSample("Combine");
            {
                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSR_SceneColor_RT", SSR_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSR_UVWPdf", SSR_OutputIDs.UVWPdf);
                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSR_ColorMask", SSR_OutputIDs.ColorMask);
                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSR_FinalColor", SSR_OutputIDs.SpatialFilter);


                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSR_Out_Combine", SSR_OutputIDs.Combine);
                cmd.DispatchCompute(settings.computeShader, k4, width / 8, height / 8, 1);
            }
            cmd.EndSample("Combine");

            cmd.Blit(SSR_OutputIDs.Combine, renderingData.cameraData.renderer.cameraColorTargetHandle);

            cmd.ReleaseTemporaryRT(SSR_OutputIDs.UVWPdf);
            cmd.ReleaseTemporaryRT(SSR_OutputIDs.ColorMask);
        }

        UpdatePreviousTransformMatrix(renderingData.cameraData.camera);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}