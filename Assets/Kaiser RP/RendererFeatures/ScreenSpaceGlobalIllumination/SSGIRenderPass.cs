using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSGIRenderPass : ScriptableRenderPass
{
    private SSGISettings settings; //基本参数
    private Material material; //材质

    private static class SSGI_InputIDs
    {
        public static int SceneColor = Shader.PropertyToID("_SSGI_SceneColor_RT");
        public static int PyramidDepth = Shader.PropertyToID("_PyramidDepth");
    }

    private static class SSGI_OutputIDs
    {

        public static int PrevTexture = Shader.PropertyToID("_SSGI_PrevTexture");
        public static int CurrTexture = Shader.PropertyToID("_SSGI_CurrTexture");
        public static int OutCurrTexture = Shader.PropertyToID("_SSGI_Out_CurrTexture");

        public static int SpatialTexture = Shader.PropertyToID("_SSGI_SpatialTexture");
        public static int SpatialSwapTexture = Shader.PropertyToID("_SSGI_SpatialTexture_Swap");

        public static int ColorMask = Shader.PropertyToID("_SSGI_Out_ColorMask");
        public static int Combine = Shader.PropertyToID("_SSGI_Out_Combine");
    }

    private static class SSGI_Matrix
    {
        public static Matrix4x4 Proj;
        public static Matrix4x4 InvProj;
        public static Matrix4x4 InvViewProj;
        public static Matrix4x4 ViewProj;
        public static Matrix4x4 PrevViewProj;
    }

    public SSGIRenderPass(SSGISettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        profilingSampler = new ProfilingSampler("[Kaiser] SSSGI");
    }
    private RandomSampler randomSampler = new RandomSampler(0, 64);
    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        // randomSampler = new RandomSampler(0, 64);
    }

    void UpdateTransformMatrix(CommandBuffer cmd, Camera camera, int width, int height)
    {
        SSGI_Matrix.Proj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
        SSGI_Matrix.InvProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSGI_Matrix.InvViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSGI_Matrix.ViewProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false) * camera.worldToCameraMatrix;

        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_ProjMatrix", SSGI_Matrix.Proj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_InvProjMatrix", SSGI_Matrix.InvProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_InvViewProjMatrix", SSGI_Matrix.InvViewProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_ViewProjMatrix", SSGI_Matrix.ViewProj);

        Vector4 SSGI_ProjInfo = new Vector4
        ((-2 / (width * SSGI_Matrix.Proj[0])),
        (-2 / (height * SSGI_Matrix.Proj[5])),
        ((1 - SSGI_Matrix.Proj[2]) / SSGI_Matrix.Proj[0]),
        ((1 + SSGI_Matrix.Proj[6]) / SSGI_Matrix.Proj[5]));

        cmd.SetComputeVectorParam(settings.computeShader, "_SSGI_ProjInfo", SSGI_ProjInfo);
    }

    void UpdatePreviousTransformMatrix(CommandBuffer cmd, Camera camera)
    {
        SSGI_Matrix.PrevViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;

        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_PrevViewProjMatrix", SSGI_Matrix.PrevViewProj);
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

        cmd.GetTemporaryRT(SSGI_InputIDs.SceneColor, descriptorDefault);

        cmd.GetTemporaryRT(SSGI_OutputIDs.SpatialTexture, descriptorDefault);
        cmd.GetTemporaryRT(SSGI_OutputIDs.SpatialSwapTexture, descriptorDefault);

        cmd.GetTemporaryRT(SSGI_OutputIDs.PrevTexture, descriptorDefault);
        cmd.GetTemporaryRT(SSGI_OutputIDs.CurrTexture, descriptorDefault);
        cmd.GetTemporaryRT(SSGI_OutputIDs.OutCurrTexture, descriptorDefault);
        cmd.GetTemporaryRT(SSGI_OutputIDs.ColorMask, descriptorDefault);
        cmd.GetTemporaryRT(SSGI_OutputIDs.Combine, descriptorDefault);

    }

    void UpdateParameters(CommandBuffer cmd, int width, int height)
    {
        // Init SSGI Settings
        cmd.SetComputeVectorParam(settings.computeShader, "_SSGI_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
        cmd.SetComputeIntParam(settings.computeShader, "_SSGI_CastRayCount", settings.SSGI_CastRayCount);
        cmd.SetComputeIntParam(settings.computeShader, "_SSGI_FrameIndex", randomSampler.frameIndex);
        cmd.SetComputeVectorParam(settings.computeShader, "_SSGI_Jitter", randomSampler.GetRandomOffset());
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Intensity", settings.SSGI_Intensity);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Thickness", settings.SSGI_Thickness);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_ScreenFade", settings.SSGI_ScreenFade);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_TemporalWeight", settings.Temporal_Weight);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_TemporalScale", settings.Temporal_Scale);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Thickness", settings.SSGI_Thickness);

        // Init Linear Trace Settings
        cmd.SetComputeIntParam(settings.computeShader, "_Linear_MaxRaySteps", settings.Linear_MaxRaySteps);
        cmd.SetComputeFloatParam(settings.computeShader, "_Linear_RayTraceMaxDistance", settings.Linear_RayTraceMaxDistance);

        // Init Hiz Trace Settings
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxRaySteps", settings.SSGI_MaxRaySteps);
    }

    void ReleaseTemporaryRT(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(SSGI_InputIDs.SceneColor);
        cmd.ReleaseTemporaryRT(SSGI_OutputIDs.ColorMask);
        cmd.ReleaseTemporaryRT(SSGI_OutputIDs.Combine);
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();
        int k1;
        if (settings.SSGI_TraceType == SSGISettings.TraceType.Linear)
        {
            k1 = settings.computeShader.FindKernel("SSGI_RayTracing_Linear");
        }
        else
        {
            k1 = settings.computeShader.FindKernel("SSGI_RayTracing_Hiz");
        }

        int k2 = settings.computeShader.FindKernel("SSGI_Temporal");
        int k3 = settings.computeShader.FindKernel("SSGI_Bilateralfilter_X");
        int k4 = settings.computeShader.FindKernel("SSGI_Bilateralfilter_Y");
        int k5 = settings.computeShader.FindKernel("SSGI_Combine");

        using (new ProfilingScope(cmd, profilingSampler))
        {
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;

            randomSampler.RefreshFrame();

            UpdateTransformMatrix(cmd, renderingData.cameraData.camera, width, height);
            UpdateRenderTextures(cmd, width, height);
            UpdateParameters(cmd, width, height);

            cmd.BeginSample("Ray Tracing");
            {
                // Init Input Texture
                cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), SSGI_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_SceneColor_RT", SSGI_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_PyramidDepth_RT", SSGI_InputIDs.PyramidDepth);

                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_Out_ColorMask", SSGI_OutputIDs.CurrTexture);

                // Dispatch
                cmd.DispatchCompute(settings.computeShader, k1, width / 8, height / 8, 1);
            }
            cmd.EndSample("Ray Tracing");

            cmd.BeginSample("Spatial Filter");
            {
                cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Spatial_Radius", settings.BilateralFilterRadius);

                cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSGI_SpatialTexture", SSGI_OutputIDs.CurrTexture);
                cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSGI_Out_SpatialTexture", SSGI_OutputIDs.SpatialSwapTexture);
                cmd.DispatchCompute(settings.computeShader, k3, width / 8, height / 8, 1);

                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSGI_SpatialTexture", SSGI_OutputIDs.SpatialSwapTexture);
                cmd.SetComputeTextureParam(settings.computeShader, k4, "_SSGI_Out_SpatialTexture", SSGI_OutputIDs.CurrTexture);
                cmd.DispatchCompute(settings.computeShader, k4, width / 8, height / 8, 1);
            }
            cmd.EndSample("Spatial Filter");

            cmd.BeginSample("Temporal Filter");
            {
                cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_TemporalWeight", settings.Temporal_Weight);

                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSGI_PrevTexture", SSGI_OutputIDs.PrevTexture);
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSGI_CurrTexture", SSGI_OutputIDs.CurrTexture);
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSGI_Out_CurrTexture", SSGI_OutputIDs.OutCurrTexture);

                cmd.DispatchCompute(settings.computeShader, k2, width / 8, height / 8, 1);

                cmd.CopyTexture(SSGI_OutputIDs.OutCurrTexture, SSGI_OutputIDs.PrevTexture);
            }
            cmd.EndSample("Temporal Filter");

            cmd.BeginSample("Combine");
            {
                cmd.SetComputeTextureParam(settings.computeShader, k5, "_SSGI_SceneColor_RT", SSGI_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k5, "_SSGI_ColorMask", SSGI_OutputIDs.OutCurrTexture);
                cmd.SetComputeTextureParam(settings.computeShader, k5, "_SSGI_Out_Combine", SSGI_OutputIDs.Combine);
                cmd.DispatchCompute(settings.computeShader, k5, width / 8, height / 8, 1);
            }
            cmd.EndSample("Combine");

            if (settings.Debug_ColorMask)
            {
                cmd.Blit(SSGI_OutputIDs.OutCurrTexture, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }
            else
            {
                cmd.Blit(SSGI_OutputIDs.Combine, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }

            ReleaseTemporaryRT(cmd);
        }

        UpdatePreviousTransformMatrix(cmd, renderingData.cameraData.camera);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}