using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserAmbientOcclusion : ScriptableRendererFeature
{

    // public HBAORenderPass hbaoRenderPass;
    public AmbientOcclusionRenderPass aoRenderPass;
    public AmbientOcclusionSettings settings = new AmbientOcclusionSettings();

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        // throw new System.NotImplementedException();
        // hbaoRenderPass.Setup(settings);
        // hbaoRenderPass.cameraColorTarget = renderer.cameraColorTarget;
        if (renderingData.cameraData.camera.cameraType == CameraType.Game)
        {
            renderer.EnqueuePass(aoRenderPass);
        }
    }

    public override void Create()
    {
        // throw new System.NotImplementedException();
        // hbaoRenderPass = new HBAORenderPass(settings);
        aoRenderPass = new AmbientOcclusionRenderPass(settings);
    }
}
