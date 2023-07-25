using System.Collections.Generic;
using static UnityEngine.Rendering.Universal.TAARenderFeature;

namespace UnityEngine.Rendering.Universal
{
    public class TAARenderFeature : ScriptableRendererFeature
    {
        [SerializeField]
        public enum TAAQuality
        {
            High,
            Middle,
            Low,
        }

        internal sealed class TAAData
        {
            internal Matrix4x4 projPreview;
            internal Matrix4x4 viewPreview;
            internal Matrix4x4 projJitter;
            internal Vector2 offset;
            internal float blend;
            internal TAAQuality quality;
        }

        static ScriptableRendererFeature s_Instance;
        private bool isFirstFrame;

        public TAAQuality quality = TAAQuality.High;
        [Range(0.0f, 3.0f)] public float jitterIntensity = 1.0f;
        [Range(0.0f, 1.0f)] public float blend = 0.1f;

        private TAAJitterPass taaJitterPass;
        private TAARenderPass taaRenderPass;
        Dictionary<Camera, TAAData> m_TAADataCaches;

        Matrix4x4 viewPreview;
        Matrix4x4 projPreview;

        public override void Create()
        {
            s_Instance = this;
            isFirstFrame = true;
            name = "TAA";
            taaJitterPass = new TAAJitterPass();
            taaRenderPass = new TAARenderPass();
            m_TAADataCaches = new Dictionary<Camera, TAAData>();
        }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            if (renderingData.cameraData.camera.cameraType != CameraType.Game) return;
            if (isFirstFrame)
            {
                isFirstFrame = false;
                return;
            }

            Camera camera = renderingData.cameraData.camera;
            if (!m_TAADataCaches.TryGetValue(camera, out TAAData data))
            {
                data = new TAAData();
                m_TAADataCaches.Add(camera, data);
            }
            UpdateTAAData(camera, data);

            taaJitterPass.SetUp(data);
            renderer.EnqueuePass(taaJitterPass);

            taaRenderPass.Setup(data);
            renderer.EnqueuePass(taaRenderPass);
        }

        private void UpdateTAAData(Camera camera, TAAData taaData)
        {
            Vector2 jitter = TAAUtils.GetHaltonSequence9() * jitterIntensity;
            taaData.offset = new Vector2(jitter.x / camera.scaledPixelWidth, jitter.y / camera.scaledPixelHeight);
            taaData.projPreview = projPreview;
            taaData.viewPreview = viewPreview;
            taaData.projJitter = TAAUtils.GetJitteredPerspectiveProjectionMatrix(camera, jitter);
            taaData.blend = blend;
            taaData.quality = quality;

            projPreview = camera.projectionMatrix;
            viewPreview = camera.worldToCameraMatrix;
        }
    }
}


