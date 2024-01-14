using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.PlayerLoop;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class ReflectionRenderPass : ScriptableRenderPass
{
    private readonly KaiserReflection.Settings settings;
    private readonly RandomSampler randomSampler;
    private class Reflection_Output
    {
        // public static int ColorMask = Shader.PropertyToID("SSR_ColorMask");
        public static RTHandle ColorMask;
        public static RTHandle TemporalPrev;
        public static RTHandle TemporalCurr;
        public static RTHandle SpatialOut;
        public static RTHandle SpatialOut1;
    }

    private class Reflection_Matrix
    {
        public static Matrix4x4 PrevViewProj;
    }

    private static int ssrID = Shader.PropertyToID("_SSR_ColorMask_RT");

    public ReflectionRenderPass(KaiserReflection.Settings settings)
    {
        this.settings = settings;
        renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        randomSampler = new RandomSampler(0, 1024);
        profilingSampler = new ProfilingSampler("[Kaiser RP] Reflection");


    }

    // public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    // {
    //     ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
    // }

    void UpdatePreviousTransformMatrix(CommandBuffer cmd, RenderingData renderingData)
    {
        Reflection_Matrix.PrevViewProj =
            renderingData.cameraData.GetGPUProjectionMatrix() *
            renderingData.cameraData.GetViewMatrix();

        cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_PrevViewProjMatrix", Reflection_Matrix.PrevViewProj);
    }

    public void InitializeRTHandles(int width, int height)
    {
        RenderTextureDescriptor descriptor = new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGB64, 0);
        descriptor.enableRandomWrite = true;

        RenderingUtils.ReAllocateIfNeeded(ref Reflection_Output.ColorMask, descriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSR_RT");
        RenderingUtils.ReAllocateIfNeeded(ref Reflection_Output.TemporalPrev, descriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSR_HistoryBuffer0_RT");
        RenderingUtils.ReAllocateIfNeeded(ref Reflection_Output.TemporalCurr, descriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSR_HistoryBuffer1_RT");
        RenderingUtils.ReAllocateIfNeeded(ref Reflection_Output.SpatialOut, descriptor, FilterMode.Point, TextureWrapMode.Clamp, name: "_SSR_SpatialOut_RT");
    }

    public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
    {
        int width = renderingData.cameraData.camera.pixelWidth;
        int height = renderingData.cameraData.camera.pixelHeight;
        if (settings.resolution == KaiserReflection.Resolution.Half)
        {
            width /= 2;
            height /= 2;
        }
        InitializeRTHandles(width, height);
        // UpdatePreviousTransformMatrix(cmd, renderingData);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, profilingSampler))
        {
            randomSampler.RefreshFrame();

            int width = renderingData.cameraData.camera.pixelWidth;
            int height = renderingData.cameraData.camera.pixelHeight;

            int k1 = settings.computeShader.FindKernel("SSR_RayTracing_Linear");
            int k2 = settings.computeShader.FindKernel("SSR_TemporalFilter");
            int k3 = settings.computeShader.FindKernel("SSR_SpatialFilter");


            if (settings.resolution == KaiserReflection.Resolution.Half)
            {
                width /= 2;
                height /= 2;
            }
            int threadGroupsX = Mathf.CeilToInt(width / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(height / 8.0f);

            var source = renderingData.cameraData.renderer.cameraColorTargetHandle;// renderingData.cameraData.renderer.GetCameraColorBackBuffer(cmd);
                                                                                   // var source = renderingData.cameraData.renderer.GetCameraColorBackBuffer(cmd);


            // cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_PrevViewProjMatrix", renderingData.cameraData.camera.previousViewProjectionMatrix);



            cmd.SetComputeFloatParam(settings.computeShader, "_SSR_SmoothMultiplier", settings.smoothMultiplier);
            cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Intensity", settings.intensity);

            
            cmd.SetComputeVectorParam(settings.computeShader, "_SSR_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
            cmd.SetComputeIntParam(settings.computeShader, "_SSR_FrameIndex", randomSampler.frameIndex);
            cmd.SetComputeVectorParam(settings.computeShader, "_SSR_Jitter", randomSampler.GetRandomOffset());
            cmd.SetComputeVectorParam(settings.computeShader, "_SSR_Random", new Vector4(Random.value, Random.value, Random.value, Random.value));
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_In_SceneColor_RT", source);
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_In_BlueNoise_RT", settings.blueNoise);
            cmd.SetComputeTextureParam(settings.computeShader, k1, "_SSR_ColorMask_RT", Reflection_Output.ColorMask);
            cmd.DispatchCompute(settings.computeShader, k1, threadGroupsX, threadGroupsY, 1);

            cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Temporal_Prev_RT", Reflection_Output.TemporalPrev);
            cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Temporal_Curr_RT", Reflection_Output.ColorMask);
            cmd.SetComputeTextureParam(settings.computeShader, k2, "_SSR_Temporal_Out_RT", Reflection_Output.TemporalCurr);
            cmd.DispatchCompute(settings.computeShader, k2, threadGroupsX, threadGroupsY, 1);

            cmd.CopyTexture(Reflection_Output.TemporalCurr, Reflection_Output.TemporalPrev);

            cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_In_SceneColor_RT", source);

            cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_Spatial_In_RT", Reflection_Output.TemporalCurr);
            cmd.SetComputeTextureParam(settings.computeShader, k3, "_SSR_Spatial_Out_RT", Reflection_Output.SpatialOut);
            cmd.DispatchCompute(settings.computeShader, k3, threadGroupsX, threadGroupsY, 1);
            // Blitter.BlitCameraTexture(cmd, Reflection_Output.ColorMask, renderingData.cameraData.renderer.cameraColorTargetHandle);

            if (settings.reflectionType == KaiserReflection.ReflectionType.DebugColorMask)
                Blitter.BlitCameraTexture(cmd, Reflection_Output.ColorMask, renderingData.cameraData.renderer.cameraColorTargetHandle);
            else if (settings.reflectionType == KaiserReflection.ReflectionType.DebugTemporal)
                Blitter.BlitCameraTexture(cmd, Reflection_Output.TemporalCurr, renderingData.cameraData.renderer.cameraColorTargetHandle);
            else if (settings.reflectionType == KaiserReflection.ReflectionType.DebugSpatial)
                Blitter.BlitCameraTexture(cmd, Reflection_Output.SpatialOut, renderingData.cameraData.renderer.cameraColorTargetHandle);
            else
                Blitter.BlitCameraTexture(cmd, Reflection_Output.SpatialOut, renderingData.cameraData.renderer.cameraColorTargetHandle);

            // Blitter.BlitCameraTexture(cmd, Reflection_Output.HistoryBuffer[(historyIndex + 1) % 2], Reflection_Output.HistoryBuffer[historyIndex]);
        }

        // if (Reflection_Output.ColorMask != null)
        //     cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.ColorMask.name));
        // if (Reflection_Output.TemporalPrev != null)
        //     cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.TemporalPrev.name));
        // if (Reflection_Output.TemporalCurr != null)
        //     cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.TemporalCurr.name));
        UpdatePreviousTransformMatrix(cmd, renderingData);

        context.ExecuteCommandBuffer(cmd);
        cmd.Clear();
        CommandBufferPool.Release(cmd);
    }
    public void Dispose()
    {
        Reflection_Output.ColorMask?.Release();
        Reflection_Output.TemporalPrev?.Release();
        Reflection_Output.TemporalCurr?.Release();
    }
    // public override void FrameCleanup(CommandBuffer cmd)
    // {
    //     // RTHandles.Release(Reflection_Output.ColorMask);
    //     // Reflection_Output.ColorMask?.Release();
    //     if (Reflection_Output.ColorMask != null)
    //         cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.ColorMask.name));
    //     if (Reflection_Output.TemporalPrev != null)
    //         cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.TemporalPrev.name));
    //     if (Reflection_Output.TemporalCurr != null)
    //         cmd.ReleaseTemporaryRT(Shader.PropertyToID(Reflection_Output.TemporalCurr.name));

    // }

    // public override void OnCameraCleanup(CommandBuffer cmd)
    // {
    //     Reflection_Output.ColorMask = null;
    //     Reflection_Output.TemporalPrev = null;
    //     Reflection_Output.TemporalCurr = null;
    // }
}