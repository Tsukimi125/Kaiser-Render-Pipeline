using System;
using static UnityEngine.Rendering.Universal.TAARenderFeature;

namespace UnityEngine.Rendering.Universal
{

    internal static class ShaderKeyWordStrings
    {
        internal static readonly string HighTAAQuality = "_High_TAA";
        internal static readonly string MiddleTAAQuality = "_Middle_TAA";
        internal static readonly string LowTAAQuality = "_Low_TAA";
    }

    internal static class ShaderConstants
    {
        public static readonly int _Jitter_Blend = Shader.PropertyToID("_Jitter_Blend");
        public static readonly int _TAA_PreTexture = Shader.PropertyToID("_TAA_PreTexture");
        public static readonly int _Preview_VP = Shader.PropertyToID("_Preview_VP");
        public static readonly int _TAA_CurInvView = Shader.PropertyToID("_Inv_view_jittered");
        public static readonly int _TAA_CurInvProj = Shader.PropertyToID("_Inv_proj_jittered");
    }

    public class TAARenderPass : ScriptableRenderPass
    {
        private const string profilerTag = "My TAA Pass";
        private ProfilingSampler taaSampler = new ProfilingSampler("TAA Pass");

        const string taaShader = "Hidden/Universal Render Pipeline/TAAShader";

        private TAAData m_TaaData;
        private Material m_Material;
        private Material material
        {
            get
            {
                if (m_Material == null)
                {
                    m_Material = new Material(Shader.Find(taaShader));
                }
                return m_Material;
            }
        }

        private RenderTexture[] historyBuffer;
        private static int s_IndexWrite = 0;

        internal TAARenderPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        }

        internal void Setup(TAAData taaData)
        {
            m_TaaData = taaData;
        }


        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("TAA Pass");
            using (new ProfilingScope(cmd, new ProfilingSampler("TAA Pass")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();

                var camera = renderingData.cameraData.camera;
                var colorTextureIdentifier = renderingData.cameraData.renderer.cameraColorTargetHandle;
                var descriptor = new RenderTextureDescriptor(camera.scaledPixelWidth, camera.scaledPixelHeight, RenderTextureFormat.DefaultHDR, 16);
                TAAUtils.EnsureArray(ref historyBuffer, 2);
                TAAUtils.EnsureRenderTarget(ref historyBuffer[0], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);
                TAAUtils.EnsureRenderTarget(ref historyBuffer[1], descriptor.width, descriptor.height, descriptor.colorFormat, FilterMode.Bilinear);

                int indexRead = s_IndexWrite;
                s_IndexWrite = ++s_IndexWrite % 2;

                Matrix4x4 inv_p_jittered = Matrix4x4.Inverse(m_TaaData.projJitter);
                Matrix4x4 inv_v_jittered = Matrix4x4.Inverse(camera.worldToCameraMatrix);
                Matrix4x4 preview_vp = m_TaaData.projPreview * m_TaaData.viewPreview;
                material.SetMatrix(ShaderConstants._TAA_CurInvView, inv_v_jittered);
                material.SetMatrix(ShaderConstants._TAA_CurInvProj, inv_p_jittered);
                material.SetMatrix(ShaderConstants._Preview_VP, preview_vp);
                material.SetVector(ShaderConstants._Jitter_Blend, new Vector4(m_TaaData.offset.x, m_TaaData.offset.y, m_TaaData.blend, 0.0f));
                material.SetTexture(ShaderConstants._TAA_PreTexture, historyBuffer[indexRead]);
                CoreUtils.SetKeyword(cmd, ShaderKeyWordStrings.HighTAAQuality, m_TaaData.quality == TAARenderFeature.TAAQuality.High);
                CoreUtils.SetKeyword(cmd, ShaderKeyWordStrings.MiddleTAAQuality, m_TaaData.quality == TAARenderFeature.TAAQuality.Middle);
                CoreUtils.SetKeyword(cmd, ShaderKeyWordStrings.LowTAAQuality, m_TaaData.quality == TAARenderFeature.TAAQuality.Low);

                cmd.Blit(colorTextureIdentifier, historyBuffer[s_IndexWrite], material);
                cmd.Blit(historyBuffer[s_IndexWrite], colorTextureIdentifier);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}
