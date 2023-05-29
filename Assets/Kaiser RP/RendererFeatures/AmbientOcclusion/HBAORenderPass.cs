using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class HBAORenderPass : ScriptableRenderPass
{
    private HBAOSettings settings; //基本参数
    private Material material; //pass所使用的材质
    private ComputeBuffer noiseCB; //噪声数据
    public RenderTargetIdentifier cameraColorTarget; //当前摄像机的渲染对象

    private static readonly int hbaoRTId = Shader.PropertyToID("_HBAORT");
    private static readonly int hbaoBlurRTId = Shader.PropertyToID("_HBAOBlurRT");
    private static readonly int noiseCBId = Shader.PropertyToID("_NoiseCB");
    private static readonly int sampleNumsId = Shader.PropertyToID("_SampleNums");
    private static readonly int intensityId = Shader.PropertyToID("_Intensity");
    private static readonly int radiusId = Shader.PropertyToID("_Radius");
    private static readonly int maxDistanceId = Shader.PropertyToID("_MaxDistance");
    private static readonly int angleBiasId = Shader.PropertyToID("_AngleBias");
    private static readonly int aoTexId = Shader.PropertyToID("_AOTex");
    private static readonly int aoMultiplierId = Shader.PropertyToID("_AOMultiplier");

    private static readonly int blurDeltaUVId = Shader.PropertyToID("_BlurDeltaUV");


    public HBAORenderPass(HBAOSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机

        if (noiseCB != null)
        {
            noiseCB.Release();
        }

        Vector2[] noiseData = GenerateNoise();
        noiseCB = new ComputeBuffer(noiseData.Length, sizeof(float) * 2);
        noiseCB.SetData(noiseData);


        profilingSampler = new ProfilingSampler("HBAO");
    }


    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

        if (noiseCB != null)
        {
            noiseCB.Release();
        }
        if (material == null && settings.shader != null)
        {
            //通过此方法创建所需材质
            material = CoreUtils.CreateEngineMaterial(settings.shader);
        }
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        var cmd = CommandBufferPool.Get();

        using (new ProfilingScope(cmd, profilingSampler))
        {
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;
            float fov = renderingData.cameraData.camera.fieldOfView;
            float tanHalfFovY = Mathf.Tan(0.5f * fov * Mathf.Deg2Rad);

            cmd.SetGlobalBuffer(noiseCBId, noiseCB);
            cmd.SetGlobalFloat(intensityId, settings.intensity);
            cmd.SetGlobalFloat(radiusId, settings.radius * 0.5f * height / (2.0f * tanHalfFovY));
            cmd.SetGlobalFloat(sampleNumsId, settings.sampleNums);
            cmd.SetGlobalFloat(maxDistanceId, settings.maxDistance);
            // cmd.SetGlobalFloat(negInvRadius2_ID, -1.0f / (settings.radius * settings.radius));
            // float maxRadiusPixels = settings.maxRadiusPixels * Mathf.Sqrt((width * height) / (1080.0f * 1920.0f));
            // cmd.SetGlobalFloat(maxRadiusPixelsId, Mathf.Max(16, maxRadiusPixels));
            // cmd.SetGlobalFloat(angleBiasId, settings.angleBias);
            // cmd.SetGlobalFloat(aoMultiplierId, 2.0f / (1.0f - settings.angleBias));
            // cmd.SetGlobalFloat(maxDistanceId, settings.maxDistance);
            // cmd.SetGlobalFloat(distanceFalloffId, settings.distanceFalloff);

            // 1. Sample AO
            cmd.GetTemporaryRT(hbaoRTId, width, height, 0, FilterMode.Bilinear, RenderTextureFormat.R8, RenderTextureReadWrite.Linear);

            cmd.SetRenderTarget(hbaoRTId);
            CoreUtils.DrawFullScreen(cmd, material, null, 0);

            // 2.Blur
            cmd.SetGlobalVector(blurDeltaUVId, new Vector4(1.0f / width, 0, 0, 0));
            cmd.GetTemporaryRT(hbaoBlurRTId, width, height, 0, FilterMode.Bilinear, RenderTextureFormat.R8, RenderTextureReadWrite.Linear);
            cmd.SetGlobalTexture(aoTexId, hbaoRTId);
            cmd.SetRenderTarget(hbaoBlurRTId);
            CoreUtils.DrawFullScreen(cmd, material, null, 1);

            cmd.SetGlobalVector(blurDeltaUVId, new Vector4(0, 1.0f / height, 0, 0));
            cmd.SetGlobalTexture(aoTexId, hbaoBlurRTId);
            cmd.SetRenderTarget(hbaoRTId);
            CoreUtils.DrawFullScreen(cmd, material, null, 1);

            // 3.Combine

            cmd.ReleaseTemporaryRT(hbaoRTId);
            cmd.ReleaseTemporaryRT(hbaoBlurRTId);

        }

        OnDestroy();
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
    private Vector2[] GenerateNoise()
    {
        Vector2[] noises = new Vector2[4 * 4];

        for (int i = 0; i < noises.Length; i++)
        {
            float x = Random.value;
            float y = Random.value;
            noises[i] = new Vector2(x, y);
        }

        return noises;
    }


    public void OnDestroy()
    {
        if (noiseCB != null)
        {
            noiseCB.Release();
            noiseCB = null;
        }
    }
}
