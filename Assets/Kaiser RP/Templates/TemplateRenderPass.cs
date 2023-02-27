using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
/*
public class TemplateRenderPass : ScriptableRenderPass
{
    private TemplateSettings settings; //基本参数
    private Material material; //材质

    public TemplateRenderPass(TemplateSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机\
        profilingSampler = new ProfilingSampler("Ambient Occlusion");
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

        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}*/