using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricLightRenderPass : ScriptableRenderPass
{
    private KaiserVolumetricLight.Settings settings; //基本参数
    private Material material; //材质
    private ComputeShader computeShader;

    # region shader parameters
    readonly int volumetricRTId = Shader.PropertyToID("_Volumetric_RT");
    static readonly int intensity = Shader.PropertyToID("_Intensity");

    #endregion

    public VolumetricLightRenderPass(KaiserVolumetricLight.Settings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.renderPassEvent; //设置Pass的渲染时机\
        profilingSampler = new ProfilingSampler("[Kaiser] Volumetric Light");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

        if (material == null && settings.computeShader != null)
        {
            // 通过此方法创建所需材质
            // material = CoreUtils.CreateEngineMaterial(settings.shader);
        }
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

            cmd.SetComputeVectorParam(settings.computeShader, "_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));

            int volumetricKernel = settings.computeShader.FindKernel("VolumetricLight");

            cmd.GetTemporaryRT(volumetricRTId, descriptor);
            cmd.SetComputeTextureParam(settings.computeShader, volumetricKernel, "_Volumetric_RT", volumetricRTId);
            cmd.DispatchCompute(settings.computeShader, volumetricKernel, width / 8, height / 8, 1);
            cmd.ReleaseTemporaryRT(volumetricRTId);
        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}
