using System.Collections;
using System.Collections.Generic;
using System.Configuration;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class RTRRenderPass : ScriptableRenderPass
{
    private KaiserReflection.Settings settings; //基本参数
    private Material material;
    private RayTracingShader rayTracingShader;
    private RayTracingAccelerationStructure accelerationStructure;

    private static class Reflection_OutputIDs
    {
        public static int UVWPDF = Shader.PropertyToID("RTR_UVWPDF");
    }

    public RTRRenderPass(KaiserReflection.Settings settings)
    {
        this.settings = settings;
        profilingSampler = new ProfilingSampler("[Kaiser RP] Reflection");
        accelerationStructure = new RayTracingAccelerationStructure();
        accelerationStructure.Build();
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, profilingSampler))
        {
            int width = renderingData.cameraData.camera.pixelWidth;
            int height = renderingData.cameraData.camera.pixelHeight;

            if (settings.resolution == KaiserReflection.Resolution.Half)
            {
                width /= 2;
                height /= 2;
            }

            if (settings.reflectionType == KaiserReflection.ReflectionType.StochasticSSR)
            {

            }
            else
            {
                // RenderTextureDescriptor descriptorDefault = new RenderTextureDescriptor(
                //     width, height, RenderTextureFormat.Default, 0, 0);
                // descriptorDefault.sRGB = false;
                // descriptorDefault.enableRandomWrite = true;

                // cmd.GetTemporaryRT(Reflection_OutputIDs.UVWPDF, descriptorDefault);

                // cmd.SetRayTracingVectorParam(settings.rayTracingShader, "RTR_TraceResolution", new Vector4(width, height, 1.0f / width, 1.0f / height));

                // cmd.SetRayTracingTextureParam(settings.rayTracingShader, "RTR_UVWPDF", Reflection_OutputIDs.UVWPDF);
                // cmd.SetRayTracingAccelerationStructure(settings.rayTracingShader, "_RaytracingAccelerationStructure", accelerationStructure);

                // cmd.DispatchRays(settings.rayTracingShader, "Refelction_RayGen", (uint)width, (uint)height, 1);

                // cmd.Blit(Reflection_OutputIDs.UVWPDF, renderingData.cameraData.renderer.cameraColorTargetHandle);
            }


        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}