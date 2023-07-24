using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class KaiserReflection : ScriptableRendererFeature
{
    public enum ReflectionType
    {
        StochasticSSR,
        RayTraced,
    }
    public enum Resolution
    {
        Half,
        Full,
    }

    [System.Serializable]
    public class Settings
    {

        public ReflectionType reflectionType = ReflectionType.RayTraced;
        public Resolution resolution = Resolution.Half;

        public RayTracingShader rayTracingShader;
    }


    public ReflectionRenderPass reflectionRenderPass;
    public Settings settings = new Settings();
    public override void Create()
    {
        reflectionRenderPass = new ReflectionRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(reflectionRenderPass);
    }


}
