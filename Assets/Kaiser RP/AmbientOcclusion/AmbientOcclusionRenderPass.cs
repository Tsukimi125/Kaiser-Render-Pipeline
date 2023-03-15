using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class AmbientOcclusionRenderPass : ScriptableRenderPass
{
    private AmbientOcclusionSettings settings; //基本参数

    static int aoRTId = Shader.PropertyToID("AmbientOcclusionRT");
    static int blueNoiseId = Shader.PropertyToID("_BlueNoiseTexture");
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

        using (new ProfilingScope(cmd, profilingSampler))
        {
            // Prepare
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;

            RenderTextureDescriptor descriptor = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.Default, 0, 0);
            descriptor.sRGB = false;
            descriptor.enableRandomWrite = true;
            // cmd.GetTemporaryRT(aoRTId, width, height, 0, FilterMode.Bilinear, RenderTextureFormat.R8, RenderTextureReadWrite.Default);

            // cmd.SetComputeFloatParam(settings.computeShader, "_Intensity", settings.intensity);



            Matrix4x4 projectionMatrix = renderingData.cameraData.GetProjectionMatrix();
            cmd.SetComputeVectorParam(settings.computeShader, "_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));
            cmd.SetComputeMatrixParam(settings.computeShader, "_CameraProjectionMatrix", projectionMatrix);
            cmd.SetComputeMatrixParam(settings.computeShader, "_CameraInverseProjectionMatrix", projectionMatrix.inverse);

            cmd.SetComputeFloatParam(settings.computeShader, "_Intensity", settings.intensity);
            cmd.SetComputeFloatParam(settings.computeShader, "_Radius", settings.aoRadius);

            cmd.SetComputeFloatParam(settings.computeShader, "_NegInvRadius2", -1.0f / settings.aoRadius * settings.aoRadius);
            cmd.SetComputeIntParam(settings.computeShader, "_DirectionCount", settings.directionCount);
            cmd.SetComputeIntParam(settings.computeShader, "_SampleCount", settings.sampleCount);

            int hbaoKernel = settings.computeShader.FindKernel("HBAO");

            cmd.GetTemporaryRT(aoRTId, descriptor);

            cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "_BlueNoiseTexture", blueNoiseId);
            cmd.SetComputeTextureParam(settings.computeShader, hbaoKernel, "AmbientOcclusionRT", aoRTId);

            cmd.DispatchCompute(settings.computeShader, hbaoKernel, width / 8, height / 8, 1);
            cmd.SetGlobalTexture("_AmbientOcclusionRT", aoRTId);

        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}