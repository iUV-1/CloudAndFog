using System;
using UnityEngine;
using UnityEngine.Rendering.Universal;
using UnityEngine.SceneManagement; // Required for URP features

public class RenderFeatureManager : MonoBehaviour
{
    [Tooltip("Drag your Full Screen Pass Renderer Feature here.")]
    // By using the exact class name, the inspector will ONLY accept Full Screen Passes!
    [SerializeField] private FullScreenPassRendererFeature fullScreenPass;
    [SerializeField] private float defaultDensity = 1f;
    public void Start()
    {
        string currentSceneName = SceneManager.GetActiveScene().name;
        if (currentSceneName == "FullscreenDemo")
        {
            EnableFullScreenEffect();
        }
        else
        {
            DisableFullScreenEffect();
        }
    }

    public void EnableFullScreenEffect()
    {
        if (fullScreenPass != null && fullScreenPass.passMaterial != null)
        {
            // Turn the effect ON by restoring the density
            fullScreenPass.passMaterial.SetFloat("_DensityMultiplier", defaultDensity);
        }
    }

    public void DisableFullScreenEffect()
    {
        if (fullScreenPass != null && fullScreenPass.passMaterial != null)
        {
            // Turn the effect OFF by setting density to 0
            fullScreenPass.passMaterial.SetFloat("_DensityMultiplier", 0f);
        }
    }

    // ⚠️ CRITICAL EDITOR FIX ⚠️
    // Because you are modifying a Material asset, the change will permanently save 
    // in the Unity Editor when you stop playing. This resets it so you don't lose your work!
    private void OnDisable()
    {
        if (fullScreenPass != null && fullScreenPass.passMaterial != null)
        {
            fullScreenPass.passMaterial.SetFloat("_DensityMultiplier", defaultDensity);
        }
    }

    // BONUS: Because you strictly typed the variable, you can also modify its properties!
    public void SwapMaterial(Material newMaterial)
    {
        if (fullScreenPass != null && newMaterial != null)
        {
            fullScreenPass.passMaterial = newMaterial;
        }
    }
}