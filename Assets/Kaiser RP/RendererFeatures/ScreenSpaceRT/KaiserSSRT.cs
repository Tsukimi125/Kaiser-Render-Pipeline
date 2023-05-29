using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserSSRT : ScriptableRendererFeature
{
    public SSRTRenderPass ssrtRenderPass;
    public SSRTSettings settings = new SSRTSettings();

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(ssrtRenderPass);
    }

    public override void Create()
    {
        ssrtRenderPass = new SSRTRenderPass(settings);
    }
}
