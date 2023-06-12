using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSRTRenderPass : ScriptableRenderPass
{
    private SSRTSettings settings; //基本参数
    private Material material; //材质

    int pyramidDepth_ID = Shader.PropertyToID("_PyramidDepth");

    private static class SSR_InputIDs 
    {
        public static int SceneColor = Shader.PropertyToID("_SSR_SceneColor_RT");

    }

    private static class SSR_OutputIDs
    {
        public static int UVWPdf = Shader.PropertyToID("_SSR_Out_UVWPdf");
        public static int ColorMask = Shader.PropertyToID("_SSR_Out_ColorMask");
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

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, profilingSampler))
        {
            cmd.BeginSample("Ray Tracing");
            // Prepare
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;
 
            RenderTextureDescriptor descriptor0 = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.Default, 0, 0);
            descriptor0.sRGB = false;
            descriptor0.enableRandomWrite = true;
            RenderTextureDescriptor descriptor1 = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.Default, 0, 0);
            descriptor1.sRGB = false;
            descriptor1.enableRandomWrite = true;
            RenderTextureDescriptor descriptor2 = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.Default, 0, 0);
            descriptor2.sRGB = false;
            descriptor2.enableRandomWrite = true;

            cmd.SetComputeVectorParam(settings.computeShader, "_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));

            int k1 = settings.computeShader.FindKernel("SSR_RayTracing");
            
            // Init Input
            cmd.GetTemporaryRT(SSR_InputIDs.SceneColor, descriptor0);
            cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), SSR_InputIDs.SceneColor);

            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_SceneColor_RT", SSR_InputIDs.SceneColor);
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_PyramidDepth", pyramidDepth_ID);  

            // Init Output
            cmd.GetTemporaryRT(SSR_OutputIDs.UVWPdf, descriptor1);
            cmd.GetTemporaryRT(SSR_OutputIDs.ColorMask, descriptor2);
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_UVWPdf", SSR_OutputIDs.UVWPdf);
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_Out_ColorMask", SSR_OutputIDs.ColorMask);

            

            // Init Hiz Trace Settings
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_RaySteps", settings.Hiz_RaySteps);
            cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Thickness", settings.SSR_Thickness);

            cmd.DispatchCompute(settings.computeShader, k1, width / 8, height / 8, 1);

 
            cmd.ReleaseTemporaryRT(SSR_OutputIDs.UVWPdf);
            cmd.ReleaseTemporaryRT(SSR_OutputIDs.ColorMask);

            cmd.EndSample("Ray Tracing");
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}