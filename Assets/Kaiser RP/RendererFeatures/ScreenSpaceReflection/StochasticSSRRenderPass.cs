using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class StochasticSSRRenderPass : ScriptableRenderPass
{
    private StochasticSSRSettings settings; //基本参数
    private Material material; //材质


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
        public static int TemporalFilter = Shader.PropertyToID("_SSR_Out_TemporalFilter");
        public static int TemporalPrevTexture = Shader.PropertyToID("_SSR_Temporal_PrevTexture");
        public static int TemporalCurrTexture = Shader.PropertyToID("_SSR_Temporal_CurrTexture");
        public static int Combine = Shader.PropertyToID("_SSR_Out_Combine");
    }

    private static class SSR_Matrix
    {
        public static Matrix4x4 View;
        public static Matrix4x4 InvView;
        public static Matrix4x4 Proj;
        public static Matrix4x4 InvProj;
        public static Matrix4x4 ViewProj;
        public static Matrix4x4 InvViewProj;
        public static Matrix4x4 PrevViewProj;
    }

    public StochasticSSRRenderPass(StochasticSSRSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        profilingSampler = new ProfilingSampler("[Kaiser] SSSR");
    }
    private RandomSampler randomSampler = new RandomSampler(0, 64);
    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
        // randomSampler = new RandomSampler(0, 64);
    }
    void UpdateTransformMatrix(CommandBuffer cmd, RenderingData renderingData)
    {
        // SSR_Matrix.Proj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
        // SSR_Matrix.InvProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        // SSR_Matrix.InvViewProj = camera.cameraToWorldMatrix *
        //     GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        // SSR_Matrix.ViewProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false) * camera.worldToCameraMatrix;
        // SSR_Matrix.View = camera.worldToCameraMatrix;
        SSR_Matrix.View = renderingData.cameraData.GetViewMatrix();
        SSR_Matrix.InvView = SSR_Matrix.View.inverse;
        SSR_Matrix.Proj = renderingData.cameraData.GetGPUProjectionMatrix();
        SSR_Matrix.InvProj = SSR_Matrix.Proj.inverse;
        SSR_Matrix.InvViewProj = SSR_Matrix.View.inverse * SSR_Matrix.InvProj;
        SSR_Matrix.ViewProj = SSR_Matrix.Proj * SSR_Matrix.View;


        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_InvViewMatrix", SSR_Matrix.InvView);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_ProjMatrix", SSR_Matrix.Proj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_InvProjMatrix", SSR_Matrix.InvProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_InvViewProjMatrix", SSR_Matrix.InvViewProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_ViewProjMatrix", SSR_Matrix.ViewProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_ViewMatrix", SSR_Matrix.View);
    }

    void UpdatePreviousTransformMatrix(CommandBuffer cmd, Camera camera)
    {
        SSR_Matrix.PrevViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;

        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_PrevViewProjMatrix", SSR_Matrix.PrevViewProj);
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

        cmd.GetTemporaryRT(SSR_OutputIDs.TemporalFilter, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.TemporalPrevTexture, descriptorDefault);
        cmd.GetTemporaryRT(SSR_OutputIDs.TemporalCurrTexture, descriptorDefault);

        cmd.GetTemporaryRT(SSR_OutputIDs.Combine, descriptorDefault);

    }

    void UpdateParameters(CommandBuffer cmd, int width, int height)
    {
        // Init SSR Settings
        cmd.SetComputeVectorParam(settings.computeShader, "_SSR_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
        cmd.SetComputeIntParam(settings.computeShader, "_SSR_FrameIndex", randomSampler.frameIndex);
        cmd.SetComputeVectorParam(settings.computeShader, "_SSR_Jitter", randomSampler.GetRandomOffset());
        cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Thickness", settings.SSR_Thickness);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSR_ScreenFade", settings.SSR_ScreenFade);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSR_TemporalWeight", settings.Temporal_Weight);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSR_TemporalScale", settings.Temporal_Scale);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Thickness", settings.SSR_Thickness);

        // Init Hiz Trace Settings
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_SSR_MaxRaySteps", settings.Hiz_RaySteps);
    }

    void ReleaseTemporaryRT(CommandBuffer cmd)
    {
        cmd.ReleaseTemporaryRT(SSR_InputIDs.SceneColor);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.UVWPdf);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.ColorMask);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.SpatialFilter);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.TemporalFilter);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.TemporalPrevTexture);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.TemporalCurrTexture);
        cmd.ReleaseTemporaryRT(SSR_OutputIDs.Combine);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        // int k1 = settings.computeShader.FindKernel("SSR_RayTracing_Hiz");
        int k1 = settings.computeShader.FindKernel("SSR_RayTracing_RayMarching");
        int k2 = settings.computeShader.FindKernel("SSR_SpatialFilter");
        int k3 = settings.computeShader.FindKernel("SSR_TemporalFilter");
        int k4 = settings.computeShader.FindKernel("SSR_Combine");

        using (new ProfilingScope(cmd, profilingSampler))
        {
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;

            randomSampler.RefreshFrame();

            UpdateTransformMatrix(cmd, renderingData);
            UpdateRenderTextures(cmd, width, height);
            UpdateParameters(cmd, width, height);

            cmd.BeginSample("Ray Tracing");
            {
                // Init Input Texture
                cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), SSR_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_SceneColor_RT", SSR_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_PyramidDepth_RT", SSR_InputIDs.PyramidDepth);

                // Init Output Texture
                // cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_UVWPdf", SSR_OutputIDs.UVWPdf);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_ColorMask", SSR_OutputIDs.ColorMask);

                // Dispatch
                cmd.DispatchCompute(settings.computeShader, k1, width / 8, height / 8, 1);
            }
            cmd.EndSample("Ray Tracing");

            cmd.BeginSample("Spatial Filter");
            {
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_UVWPdf", SSR_OutputIDs.UVWPdf);
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_ColorMask", SSR_OutputIDs.ColorMask);
                cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Out_SpatialFilter", SSR_OutputIDs.SpatialFilter);
                cmd.DispatchCompute(settings.computeShader, k2, width / 8, height / 8, 1);
                cmd.CopyTexture(SSR_OutputIDs.SpatialFilter, SSR_OutputIDs.TemporalCurrTexture);
            }
            cmd.EndSample("Spatial Filter");

            cmd.BeginSample("Temporal Filter");
            {
                // cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_UVWPdf", SSR_OutputIDs.UVWPdf);
                // cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_SpatialFilter", SSR_OutputIDs.TemporalCurrTexture);
                // cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_Temporal_PrevTexture", SSR_OutputIDs.TemporalPrevTexture);
                // cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_Temporal_CurrTexture", SSR_OutputIDs.TemporalCurrTexture);
                // cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_Out_TemporalFilter", SSR_OutputIDs.TemporalFilter);
                // cmd.DispatchCompute(settings.computeShader, k3, width / 8, height / 8, 1);
                // cmd.CopyTexture(SSR_OutputIDs.TemporalFilter, SSR_OutputIDs.TemporalCurrTexture);
                // cmd.CopyTexture(SSR_OutputIDs.TemporalCurrTexture, SSR_OutputIDs.TemporalPrevTexture);
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
            if (settings.debugMode == StochasticSSRSettings.DebugMode.ColorMask)
            {
                cmd.Blit(SSR_OutputIDs.ColorMask, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }
            else
            {
                cmd.Blit(SSR_OutputIDs.Combine, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }


            ReleaseTemporaryRT(cmd);
        }

        UpdatePreviousTransformMatrix(cmd, renderingData.cameraData.camera);

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}