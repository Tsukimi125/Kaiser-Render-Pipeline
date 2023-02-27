using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class VolumetricLight : ScriptableRendererFeature
{
    // Start is called before the first frame update
    public VolumetricLightRenderPass volumetricLightRenderPass;
    
    [System.Serializable]
    public class Settings
    {
        public Shader shader = null;
        public RenderPassEvent renderPassEvent = RenderPassEvent.AfterRenderingTransparents;
        public enum VolumetricLightMode
        {
            None,
            Raymarching,
            Raytracing
        }

        public int raymarchingMaxSteps = 64;
        public float raymarchingStepSize = 1f;
        public float raymarchingMaxDistance = 100f;

    };

    public Settings settings = new Settings();

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(volumetricLightRenderPass);
    }

    public override void Create()
    {
        volumetricLightRenderPass = new VolumetricLightRenderPass(settings);
    }
}
