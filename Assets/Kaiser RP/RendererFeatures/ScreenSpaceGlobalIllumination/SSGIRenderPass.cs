using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


public class SSGIRenderPass : ScriptableRenderPass
{
    SSGISettings settings;
    private static class SSGI_Matrix
    {
        public static Matrix4x4 View;
        public static Matrix4x4 Proj;
        public static Matrix4x4 InvProj;
        public static Matrix4x4 InvViewProj;
        public static Matrix4x4 ViewProj;
        public static Matrix4x4 PrevViewProj;
    }

    private static class SSGI_Input
    {
        public static int SceneColor = Shader.PropertyToID("_SSGI_SceneColor_RT");
        public static int PyramidDepth = Shader.PropertyToID("_PyramidDepth");
    }

    private static class SSGI_Output
    {
        public static int ColorMask = Shader.PropertyToID("_SSGI_Out_ColorMask_RT");
    }



    public SSGIRenderPass(SSGISettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        profilingSampler = new ProfilingSampler("[Kaiser] ScreenSpaceGlobalIllumination");
    }

    private int frameIndex = 0;
    private const int sampleCount = 64;
    private Vector2 randomSampler = new Vector2(1.0f, 1.0f);
    private float GetHaltonValue(int index, int radix)
    {
        float result = 0f;
        float fraction = 1f / radix;

        while (index > 0)
        {
            result += (index % radix) * fraction;
            index /= radix;
            fraction /= radix;
        }
        return result;
    }
    private Vector2 GenerateRandomOffset()
    {
        var offset = new Vector2(GetHaltonValue(frameIndex & 1023, 2), GetHaltonValue(frameIndex & 1023, 3));
        if (frameIndex++ >= sampleCount)
            frameIndex = 0;
        return offset;
    }


    void UpdateTransformMatrix(Camera camera)
    {
        SSGI_Matrix.View = camera.worldToCameraMatrix;
        SSGI_Matrix.Proj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false);
        SSGI_Matrix.InvProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSGI_Matrix.InvViewProj = camera.cameraToWorldMatrix *
            GL.GetGPUProjectionMatrix(camera.projectionMatrix, false).inverse;
        SSGI_Matrix.ViewProj = GL.GetGPUProjectionMatrix(camera.projectionMatrix, false) * camera.worldToCameraMatrix;
    }


    void UpdateParameters(CommandBuffer cmd, int width, int height)
    {
        randomSampler = GenerateRandomOffset();

        cmd.SetComputeIntParam(settings.computeShader, "_SSGI_FrameIndex", frameIndex);
        cmd.SetComputeIntParam(settings.computeShader, "_SSGI_CastRayCount", settings.SSGI_CastRayCount);
        cmd.SetComputeVectorParam(settings.computeShader, "_SSGI_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
        cmd.SetComputeVectorParam(settings.computeShader, "_SSGI_Jitter", new Vector2(randomSampler.x, randomSampler.y));
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Thickness", settings.SSGI_Thickness);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_ScreenFade", settings.SSGI_ScreenFade);
        cmd.SetComputeFloatParam(settings.computeShader, "_SSGI_Intensity", settings.SSGI_Intensity);


        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_ViewMatrix", SSGI_Matrix.View);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_ProjMatrix", SSGI_Matrix.Proj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_InvProjMatrix", SSGI_Matrix.InvProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_ViewProjMatrix", SSGI_Matrix.ViewProj);
        cmd.SetComputeMatrixParam(settings.computeShader, "_SSGI_InvViewProjMatrix", SSGI_Matrix.InvViewProj);

        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
        cmd.SetComputeIntParam(settings.computeShader, "_Hiz_RaySteps", settings.Hiz_RaySteps);

        cmd.SetComputeTextureParam(settings.computeShader, 0, "_SSGI_PyramidDepth_RT", settings.noiseTex);
    }
    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        // ConfigureTarget(renderingData.cameraData.renderer.cameraColorTargetHandle, renderingData.cameraData.renderer.cameraColorTargetHandle);
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
    }
    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        int k1 = settings.computeShader.FindKernel("SSGI_RayTracing");

        int width = renderingData.cameraData.cameraTargetDescriptor.width;
        int height = renderingData.cameraData.cameraTargetDescriptor.height;

        UpdateParameters(cmd, width, height);
        UpdateTransformMatrix(renderingData.cameraData.camera);

        RenderTextureDescriptor descriptorDefault = new RenderTextureDescriptor(
                    width, height, RenderTextureFormat.Default, 0, 0);
        descriptorDefault.sRGB = false;
        descriptorDefault.enableRandomWrite = true;

        RenderTextureDescriptor descriptorR8 = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.R8, 0, 0);
        descriptorR8.sRGB = false;
        descriptorR8.enableRandomWrite = true;

        using (new ProfilingScope(cmd, profilingSampler))
        {
            cmd.BeginSample("RayTracing");
            {
                cmd.GetTemporaryRT(SSGI_Input.SceneColor, descriptorDefault);
                cmd.GetTemporaryRT(SSGI_Input.PyramidDepth, descriptorDefault);
                cmd.GetTemporaryRT(SSGI_Output.ColorMask, descriptorDefault);

                cmd.Blit(renderingData.cameraData.renderer.cameraColorTargetHandle, SSGI_Input.SceneColor);
                cmd.Blit(renderingData.cameraData.renderer.cameraColorTargetHandle, SSGI_Input.SceneColor);

                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_SceneColor_RT", SSGI_Input.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_PyramidDepth_RT", SSGI_Input.PyramidDepth);
                cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSGI_Out_ColorMask_RT", SSGI_Output.ColorMask);

                cmd.DispatchCompute(settings.computeShader, k1, width / 8, height / 8, 1);
                cmd.Blit(SSGI_Output.ColorMask, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }

            cmd.EndSample("RayTracing");
        }

        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }

    public override void OnCameraCleanup(CommandBuffer cmd)
    {

    }
}