using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserPyramidDepth : ScriptableRendererFeature
{
    public PyramidDepthRenderPass renderPass;
    public PyramidDepthSettings settings = new PyramidDepthSettings();

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(renderPass);
    }
    public override void Create()
    {
        renderPass = new PyramidDepthRenderPass(settings);
    }
}
