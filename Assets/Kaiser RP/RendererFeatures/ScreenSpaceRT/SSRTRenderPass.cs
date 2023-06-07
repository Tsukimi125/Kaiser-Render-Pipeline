using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class SSRTRenderPass : ScriptableRenderPass
{
    private SSRTSettings settings; //基本参数
    private Material material; //材质
    readonly int SSR_RT_ID = Shader.PropertyToID("_SSR_RT"),
    SSR_SceneColor_ID = Shader.PropertyToID("_SSR_SceneColor_RT"),
    SSR_HierarchicalDepth_ID = Shader.PropertyToID("_SSR_HierarchicalDepth_RT"),
    SSR_HierarchicalDepth_BackUp_ID = Shader.PropertyToID("_SSR_HierarchicalDepth_BackUp_RT"),
    SSR_ProjectionMatrix_ID = Shader.PropertyToID("_SSR_ProjectionMatrix");

    RenderTexture SSR_HierarchicalDepth_RT, SSR_HierarchicalDepth_BackUp_RT;
    Matrix4x4 SSR_ProjectionMatrix;

    enum Pass {
        PrepareHiz,
    }

    public SSRTRenderPass(SSRTSettings settings)
    {
        this.settings = settings;
        this.renderPassEvent = settings.passEvent; //设置Pass的渲染时机
        profilingSampler = new ProfilingSampler("[Kaiser] ScreenSpaceRT");
    }

    public override void Configure(CommandBuffer cmd, RenderTextureDescriptor cameraTextureDescriptor)
    {
        ConfigureInput(ScriptableRenderPassInput.Depth | ScriptableRenderPassInput.Normal);

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
            // Prepare
            int width = renderingData.cameraData.cameraTargetDescriptor.width;
            int height = renderingData.cameraData.cameraTargetDescriptor.height;
            SSR_ProjectionMatrix = GL.GetGPUProjectionMatrix(renderingData.cameraData.camera.projectionMatrix, false);
            Debug.Log("SSR_ProjectionMatrix: " + SSR_ProjectionMatrix);
            RenderTextureDescriptor descriptor = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.Default, 0, 0);
            descriptor.sRGB = false;
            descriptor.enableRandomWrite = true;

            cmd.GetTemporaryRT(SSR_SceneColor_ID, descriptor);
            cmd.Blit(Shader.GetGlobalTexture("_BlitTexture"), SSR_SceneColor_ID);

            RenderTextureDescriptor Hiz_Descriptor = new RenderTextureDescriptor(
                width, height, RenderTextureFormat.RFloat, 0, 0);
            Hiz_Descriptor.sRGB = false;
            Hiz_Descriptor.enableRandomWrite = true;
            Hiz_Descriptor.useMipMap = true;
            Hiz_Descriptor.autoGenerateMips = false;

            // Hi-Z Buffer
            cmd.GetTemporaryRT(SSR_HierarchicalDepth_ID, Hiz_Descriptor);
            cmd.GetTemporaryRT(SSR_HierarchicalDepth_BackUp_ID, Hiz_Descriptor);
            
            cmd.Blit(Shader.GetGlobalTexture("_CameraDepthTexture"), SSR_HierarchicalDepth_ID);
            
            //set Hiz-depth RT
            for (int i = 0; i < settings.Hiz_MaxLevel; i++) {
               cmd.SetGlobalInt("_SSR_HiZ_PrevDepthLevel", i);
               cmd.SetRenderTarget(SSR_HierarchicalDepth_BackUp_ID, i + 1);
               cmd.DrawProcedural(Matrix4x4.identity, material, (int)Pass.PrepareHiz, MeshTopology.Triangles, 3);
               cmd.CopyTexture(SSR_HierarchicalDepth_BackUp_ID, 0, i + 1, SSR_HierarchicalDepth_ID, 0, i + 1);
            }
            // cmd.SetGlobalTexture(SSR_HierarchicalDepth_ID, SSR_HierarchicalDepth_RT);

            cmd.SetComputeVectorParam(settings.computeShader, "_BufferSize", new Vector4(width, height, 1.0f / width, 1.0f / height));

            int ssrKernel = settings.computeShader.FindKernel("SSR");

            cmd.GetTemporaryRT(SSR_RT_ID, descriptor);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_RT", SSR_RT_ID);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_NoiseTex", settings.noiseTex);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_HierarchicalDepth_RT", SSR_HierarchicalDepth_ID);
            cmd.SetComputeTextureParam(settings.computeShader, ssrKernel, "_SSR_SceneColor_RT", SSR_SceneColor_ID);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_MaxLevel", settings.Hiz_MaxLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StartLevel", settings.Hiz_StartLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_StopLevel", settings.Hiz_StopLevel);
            cmd.SetComputeIntParam(settings.computeShader, "_Hiz_RaySteps", settings.Hiz_RaySteps);
            cmd.SetComputeFloatParam(settings.computeShader, "_SSR_Thickness", settings.SSR_Thickness);
            cmd.SetComputeMatrixParam(settings.computeShader, "_SSR_ProjectionMatrix", SSR_ProjectionMatrix);
            cmd.DispatchCompute(settings.computeShader, ssrKernel, width / 8, height / 8, 1);
            cmd.ReleaseTemporaryRT(SSR_RT_ID);

        }
        context.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
    }
}