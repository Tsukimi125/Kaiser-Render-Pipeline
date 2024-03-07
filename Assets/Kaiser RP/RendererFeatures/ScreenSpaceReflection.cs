using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

internal class ScreenSpaceReflection : ScriptableRendererFeature
{
    private Shader m_Shader;
    private Material m_Material;

    private Shader m_Shader_Denoise;
    private Material m_Material_Denoise;

    public Settings m_Settings = new Settings();
    ScreenSpaceReflectionPass m_RenderPass = null;

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            m_RenderPass.Setup(renderingData);
            renderer.EnqueuePass(m_RenderPass);
        }

    }

    public override void SetupRenderPasses(ScriptableRenderer renderer, in RenderingData renderingData)
    {
        if (renderingData.cameraData.cameraType == CameraType.Game)
        {
            // Calling ConfigureInput with the ScriptableRenderPassInput.Color argument
            // ensures that the opaque texture is available to the Render Pass.
            m_RenderPass.ConfigureInput(ScriptableRenderPassInput.Color | ScriptableRenderPassInput.Motion);
            m_RenderPass.SetTarget(renderer.cameraColorTargetHandle, m_Settings);
        }
    }

    public override void Create()
    {
        m_Shader = Shader.Find("Hidden/KaiserRP/ScreenSpaceReflection");
        m_Material = CoreUtils.CreateEngineMaterial(m_Shader);
        m_RenderPass = new ScreenSpaceReflectionPass(m_Material);
    }

    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_Material);
    }

    [System.Serializable]
    internal class Settings
    {
        public float intensity = 1.0f;
        public float temporalWeight = 0.95f;
        public float denoiseKernelSizeStart = 1.0f;
        public float denoiseKernelSizeMultiplier = 2.0f;
    }

    internal class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        ProfilingSampler m_ProfilingSampler = new ProfilingSampler("[Kaiser]ScreenSpaceReflection");
        Material m_Material;
        RTHandle m_CameraColorTarget;
        Settings settings;

        static class SSRRTHandles
        {
            static public RTHandle copiedColor;
            static public RTHandle ssrTexture1;
            static public RTHandle ssrTexture2;
            static public RTHandle ssrTexture3;
        }
        private uint m_FrameIndex = 0;

        public ScreenSpaceReflectionPass(Material material)
        {
            m_Material = material;
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        public void Setup(in RenderingData renderingData)
        {
            var colorCopyDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            colorCopyDescriptor.depthBufferBits = (int)DepthBits.None;

            // Reallocate the RTHandles
            RenderingUtils.ReAllocateIfNeeded(ref SSRRTHandles.copiedColor, colorCopyDescriptor, name: "_FullscreenPassColorCopy");
            RenderingUtils.ReAllocateIfNeeded(ref SSRRTHandles.ssrTexture1, colorCopyDescriptor, name: "_SSR_Texture1");
            RenderingUtils.ReAllocateIfNeeded(ref SSRRTHandles.ssrTexture2, colorCopyDescriptor, name: "_SSR_Texture2");
            RenderingUtils.ReAllocateIfNeeded(ref SSRRTHandles.ssrTexture3, colorCopyDescriptor, name: "_SSR_Texture3");
        }

        public void SetTarget(RTHandle colorHandle, Settings settings)
        {
            m_CameraColorTarget = colorHandle;
            this.settings = settings;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ConfigureTarget(m_CameraColorTarget);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var cameraData = renderingData.cameraData;
            var source = renderingData.cameraData.renderer.cameraColorTargetHandle;
            Vector2 viewportScale = source.useScaling ? new Vector2(source.rtHandleProperties.rtHandleScale.x, source.rtHandleProperties.rtHandleScale.y) : Vector2.one;
            // Debug.Log(viewportScale);
            if (cameraData.camera.cameraType != CameraType.Game)
                return;

            if (m_Material == null)
                return;

            CommandBuffer cmd = CommandBufferPool.Get();

            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;
            
            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {
                Blitter.BlitCameraTexture(cmd, source, SSRRTHandles.copiedColor);
                m_Material.SetFloat("_Intensity", settings.intensity);
                m_Material.SetFloat("_SSR_TemporalWeight", settings.temporalWeight);
                m_Material.SetFloat("_SSR_FrameIndex", m_FrameIndex);
                float denoiseKernelSize = settings.denoiseKernelSizeStart;
                m_Material.SetFloat("_SSR_DenoiseKernelSize", denoiseKernelSize);
                m_Material.SetVector("_SSR_Resolution", new Vector4(width, height, 1.0f / width, 1.0f / height));

                m_Material.SetTexture("_SSR_ColorTexture", SSRRTHandles.copiedColor);
                
                m_Material.SetTexture("_SSR_PrevTexture", SSRRTHandles.ssrTexture1);
                // Blitter.BlitCameraTexture(cmd, source, m_CameraColorTarget, m_Material, 0);

                CoreUtils.SetRenderTarget(cmd, SSRRTHandles.ssrTexture2);
                CoreUtils.DrawFullScreen(cmd, m_Material);
                Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture2, SSRRTHandles.ssrTexture1);
                // Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture2, cameraData.renderer.cameraColorTargetHandle);
                denoiseKernelSize *= settings.denoiseKernelSizeMultiplier;
                
                m_Material.SetFloat("_SSR_DenoiseKernelSize", denoiseKernelSize);
                Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture2, SSRRTHandles.ssrTexture3, m_Material, 1);
                denoiseKernelSize *= settings.denoiseKernelSizeMultiplier;
                m_Material.SetFloat("_SSR_DenoiseKernelSize", denoiseKernelSize);
                Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture3, SSRRTHandles.ssrTexture2, m_Material, 1);
                denoiseKernelSize *= settings.denoiseKernelSizeMultiplier;
                m_Material.SetFloat("_SSR_DenoiseKernelSize", denoiseKernelSize);
                Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture2, SSRRTHandles.ssrTexture3, m_Material, 1);
                //denoiseKernelSize *= settings.denoiseKernelSizeMultiplier;
                //m_Material.SetFloat("_SSR_DenoiseKernelSize", denoiseKernelSize);
                //Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture3, SSRRTHandles.ssrTexture2, m_Material, 1);

                Blitter.BlitCameraTexture(cmd, SSRRTHandles.ssrTexture3, cameraData.renderer.cameraColorTargetHandle, m_Material, 2);

                // context.ExecuteCommandBuffer(cmd);
                // cmd.Clear();
            }


            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);

            m_FrameIndex++;
        }
    }
}