using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

internal class ScreenSpaceReflection : ScriptableRendererFeature
{
    private Shader m_Shader;
    public float m_Intensity;

    Material m_Material;

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

            m_RenderPass.SetTarget(renderer.cameraColorTargetHandle, m_Intensity);
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

    internal class ScreenSpaceReflectionPass : ScriptableRenderPass
    {
        ProfilingSampler m_ProfilingSampler = new ProfilingSampler("ScreenSpaceReflection");
        Material m_Material;
        RTHandle m_CameraColorTarget;
        float m_Intensity;
        RTHandle m_CopiedColor;

        public ScreenSpaceReflectionPass(Material material)
        {
            m_Material = material;
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        public void Setup(in RenderingData renderingData)
        {
            var colorCopyDescriptor = renderingData.cameraData.cameraTargetDescriptor;
            colorCopyDescriptor.depthBufferBits = (int)DepthBits.None;
            RenderingUtils.ReAllocateIfNeeded(ref m_CopiedColor, colorCopyDescriptor, name: "_FullscreenPassColorCopy");
        }

        public void SetTarget(RTHandle colorHandle, float intensity)
        {
            m_CameraColorTarget = colorHandle;
            m_Intensity = intensity;
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



            using (new ProfilingScope(cmd, m_ProfilingSampler))
            {

                Blitter.BlitCameraTexture(cmd, source, m_CopiedColor);
                m_Material.SetFloat("_Intensity", m_Intensity);
                m_Material.SetTexture("_SSR_ColorTexture", m_CopiedColor);
                // Blitter.BlitCameraTexture(cmd, source, m_CameraColorTarget, m_Material, 0);

                CoreUtils.SetRenderTarget(cmd, cameraData.renderer.cameraColorTargetHandle);
                CoreUtils.DrawFullScreen(cmd, m_Material);
                // context.ExecuteCommandBuffer(cmd);
                // cmd.Clear();
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();

            CommandBufferPool.Release(cmd);
        }
    }
}