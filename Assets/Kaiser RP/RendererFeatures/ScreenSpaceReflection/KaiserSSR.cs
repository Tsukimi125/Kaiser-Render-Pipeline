using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserSSR : ScriptableRendererFeature
{
    public StochasticSSRRenderPass ssrtRenderPass;
    public StochasticSSRSettings settings = new StochasticSSRSettings();
    public override void Create()
    {
        ssrtRenderPass = new StochasticSSRRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(ssrtRenderPass);
    }


}
