using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserSSGI : ScriptableRendererFeature
{
    public SSGIRenderPass m_ScriptablePass;
    public SSGISettings settings = new SSGISettings();
    public override void Create()
    {
        m_ScriptablePass = new SSGIRenderPass(settings);
        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_ScriptablePass);
    }
}


