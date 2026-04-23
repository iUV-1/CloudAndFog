using UnityEngine;
using UnityEngine.SceneManagement; // Required for loading scenes

public class SceneSwitcher : MonoBehaviour
{
    [Header("Scene Names to Load")]
    [Tooltip("The exact name of the scene to load when pressing R")]
    [SerializeField] private string r_SceneName = "Level_1";
    
    [Tooltip("The exact name of the scene to load when pressing T")]
    [SerializeField] private string t_SceneName = "Level_2";
    
    [Tooltip("The exact name of the scene to load when pressing Y")]
    [SerializeField] private string y_SceneName = "Level_3";

    void Update()
    {
        // Check for key presses every frame
        if (Input.GetKeyDown(KeyCode.R))
        {
            LoadTargetScene(r_SceneName);
        }
        else if (Input.GetKeyDown(KeyCode.T))
        {
            LoadTargetScene(t_SceneName);
        }
        else if (Input.GetKeyDown(KeyCode.Y))
        {
            LoadTargetScene(y_SceneName);
        }
    }

    private void LoadTargetScene(string sceneName)
    {
        // A quick safety check to make sure the field isn't left empty
        if (!string.IsNullOrEmpty(sceneName))
        {
            SceneManager.LoadScene(sceneName);
        }
        else
        {
            Debug.LogWarning("Scene name is empty! Please assign it in the Inspector.");
        }
    }
}