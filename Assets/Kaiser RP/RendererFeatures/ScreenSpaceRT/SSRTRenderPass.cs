using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSRTRenderPass : ScriptableRenderPass
{
    private SSRTSettings settings; //基本参数
    private Material material; //材质
    readonly int ssrRTId = Shader.PropertyToID("_SSR_RT");

    public SSRTRenderPass(SSRTSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机
        profilingSampler = new ProfilingSampler("[Kaiser] ScreenSpaceRT");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

        if (material == null && settings.shader != null)
        {
            //通过此方法创建所需材质
            material = CoreUtils.CreateEngineMaterial(settings.shader);
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

            int ssrKernel = settings.computeShader.FindKernel("SSR");

            cmd.GetTemporaryRT(ssrRTId, descriptor);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_RT", ssrRTId);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_NoiseTex", settings.noiseTex);
            cmd.DispatchCompute(settings.computeShader, ssrKernel, width / 8, height / 8, 1);       
            cmd.ReleaseTemporaryRT(ssrRTId);

        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}