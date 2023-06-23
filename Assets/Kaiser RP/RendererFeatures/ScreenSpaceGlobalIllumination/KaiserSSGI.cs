using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserSSGI : ScriptableRendererFeature
{
    public SSGIRenderPass ssgiRenderPass;
    public SSGISettings settings = new SSGISettings();
    public override void Create()
    {
        ssgiRenderPass = new SSGIRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(ssgiRenderPass);
    }


}
