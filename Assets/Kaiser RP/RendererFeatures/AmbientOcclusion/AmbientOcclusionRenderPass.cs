using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AmbientOcclusionRenderPass : ScriptableRenderPass
{
    private AmbientOcclusionSettings settings; //基本参数
    public class AO_InputIDs
    {
        public static int SceneColor = Shader.PropertyToID("_AO_In_SceneColor");

    }
    public class AO_OutputIDs
    {
        public static int AO_RT = Shader.PropertyToID("AmbientOcclusionRT");
        public static int Final_RT = Shader.PropertyToID("FinalRT");
    }

    public static int historyIndex1 = Shader.PropertyToID("_AO_Texture1");
    public static int historyIndex2 = Shader.PropertyToID("_AO_Texture2");
    public static int s_IndexWrite = 0;
    // static int aoRTId = Shader.PropertyToID("AmbientOcclusionRT");
    static int blueNoiseId = Shader.PropertyToID("_BlueNoiseTexture");

    private RandomSampler randomSampler = new RandomSampler(0, 64);

    public AmbientOcclusionRenderPass(AmbientOcclusionSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机
        profilingSampler = new ProfilingSampler("[Kaiser] Ambient Occlusion");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();
        randomSampler.RefreshFrame();



        using (new ProfilingScope(cmd, profilingSampler))
        {
            // Prepare
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;

            int hbaoKernel = settings.computeShader.FindKernel("HBAO");
            int combineKernel = settings.computeShader.FindKernel("AO_Combine");

            var camera = renderingData.cameraData.camera;
            var colorTextureIdentifier = renderingData.cameraData.renderer.cameraColorTargetHandle;
            var descriptor = new RenderTextureDescriptor(camera.scaledPixelWidth, camera.scaledPixelHeight, RenderTextureFormat.DefaultHDR, 16)
            {
                enableRandomWrite = true
            };

            // TAAUtils.EnsureArray(ref historyBuffer, 2);
            // TAAUtils.EnsureRenderTarget(ref historyBuffer[0], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);
            // TAAUtils.EnsureRenderTarget(ref historyBuffer[1], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);
            // historyBuffer[0].enableRandomWrite = true;
            // historyBuffer[1].enableRandomWrite = true;

            cmd.GetTemporaryRT(historyIndex1, descriptor);
            cmd.GetTemporaryRT(historyIndex2, descriptor);
            cmd.GetTemporaryRT(AO_InputIDs.SceneColor, descriptor);
            cmd.GetTemporaryRT(AO_OutputIDs.AO_RT, descriptor);
            cmd.GetTemporaryRT(AO_OutputIDs.Final_RT, descriptor);

            cmd.BeginSample("Compute AO");
            {
                Matrix4x4 projectionMatrix = renderingData.cameraData.GetProjectionMatrix();
                cmd.SetComputeVectorParam(settings.computeShader, "_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
                cmd.SetComputeMatrixParam(settings.computeShader, "_AO_ProjectionMatrix", projectionMatrix);
                cmd.SetComputeMatrixParam(settings.computeShader, "_AO_InverseProjectionMatrix", projectionMatrix.inverse);

                cmd.SetComputeFloatParam(settings.computeShader, "_Intensity", settings.intensity);
                cmd.SetComputeFloatParam(settings.computeShader, "_Radius", settings.aoRadius);

                cmd.SetComputeFloatParam(settings.computeShader, "_NegInvRadius2", -1.0f / settings.aoRadius * settings.aoRadius);
                cmd.SetComputeIntParam(settings.computeShader, "_DirectionCount", settings.directionCount);
                cmd.SetComputeIntParam(settings.computeShader, "_SampleCount", settings.sampleCount);
                cmd.SetComputeIntParam(settings.computeShader, "_AO_FrameIndex", randomSampler.frameIndex);

                cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "_BlueNoiseTexture", settings.blueNoiseTexture);
                // cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "AmbientOcclusionRT", AO_OutputIDs.AO_RT);
                cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "_AO_PrevTexture", historyIndex1);
                cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "AmbientOcclusionRT", historyIndex2);



                cmd.DispatchCompute(settings.computeShader, hbaoKernel, width / 8, height / 8, 1);

                // cmd.SetGlobalTexture("AmbientOcclusionRT", aoRTId);\
            }
            cmd.EndSample("Compute AO");

            cmd.BeginSample("Combine");
            {
                // Texture2D _AO_In_AmbientOcclusionRT;
                // Texture2D _AO_In_SceneColorRT;
                // RWTexture2D<float4> _AO_Out_FinalRT;
                // cmd.Blit(renderingData.cameraData.renderer.cameraColorTargetHandle, AO_InputIDs.SceneColor);
                cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), AO_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, combineKernel, "_AO_In_AmbientOcclusionRT", historyIndex2);
                cmd.SetComputeTextureParam(settings.computeShader, combineKernel, "_AO_In_SceneColorRT", AO_InputIDs.SceneColor);
                cmd.SetComputeTextureParam(settings.computeShader, combineKernel, "_AO_Out_FinalRT", AO_OutputIDs.Final_RT);
                cmd.DispatchCompute(settings.computeShader, combineKernel, width / 8, height / 8, 1);

                cmd.Blit(AO_OutputIDs.Final_RT, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }
            cmd.EndSample("Combine");

            // swap
            cmd.CopyTexture(historyIndex2, historyIndex1);


            cmd.ReleaseTemporaryRT(AO_OutputIDs.AO_RT);
            cmd.ReleaseTemporaryRT(AO_OutputIDs.Final_RT);
            cmd.ReleaseTemporaryRT(AO_InputIDs.SceneColor);

        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}