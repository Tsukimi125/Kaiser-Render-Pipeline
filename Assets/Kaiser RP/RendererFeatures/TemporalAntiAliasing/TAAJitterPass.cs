using static UnityEngine.Rendering.Universal.TAARenderFeature;

namespace UnityEngine.Rendering.Universal
{
    public class TAAJitterPass : ScriptableRenderPass
    {
        private TAAData m_TaaData;

        internal TAAJitterPass()
        {
            renderPassEvent = RenderPassEvent.BeforeRenderingGbuffer;
        }

        internal void SetUp(TAAData taaData)
        {
            m_TaaData = taaData;
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("TAA Jitter Setup");

            using (new ProfilingScope(cmd, new ProfilingSampler("TAA Jitter Setup")))
            {
                context.ExecuteCommandBuffer(cmd);
                cmd.Clear();
                Camera camera = renderingData.cameraData.camera;
                cmd.SetViewProjectionMatrices(camera.worldToCameraMatrix, m_TaaData.projJitter);
            }
            context.ExecuteCommandBuffer(cmd);
            cmd.Clear();
            CommandBufferPool.Release(cmd);
        }
    }
}

