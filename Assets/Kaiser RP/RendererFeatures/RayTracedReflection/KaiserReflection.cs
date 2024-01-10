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

        public ReflectionType reflectionType = ReflectionType.StochasticSSR;
        public ComputeShader computeShader;
        public Resolution resolution = Resolution.Half;
        public Texture2D blueNoise;

        // public RayTracingShader rayTracingShader;
    }

    public ReflectionRenderPass reflectionRenderPass;
    public Settings settings = new Settings();
    public override void Create()
    {
        reflectionRenderPass = new ReflectionRenderPass(settings);
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.camera.cameraType == CameraType.Game)
        {
            renderer.EnqueuePass(reflectionRenderPass);
        }
    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        reflectionRenderPass.ConfigureInput(ScriptableRenderPassInput.Color);
        // reflectionRenderPass.Setup(renderer.cameraColorTarget);
    }
    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        reflectionRenderPass.Dispose();
    }


}