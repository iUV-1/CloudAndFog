using UnityEngine;

/// <summary>
/// Attach to the parent GameObject that contains Main Camera.
/// Drag the Directional Light into the lightTransform field in the Inspector.
///
/// WASD        — move camera rig (relative to camera facing direction)
/// Q / E       — move down / up
/// Mouse drag  — look around (hold right mouse button)
/// IJKL        — rotate directional light (I/K = tilt up/down, J/L = swing left/right)
/// </summary>
public class SceneController : MonoBehaviour
{
    [Header("Camera Movement")]
    public float moveSpeed   = 10f;
    public float sprintMult  = 3f;   // hold Left Shift to sprint
    public float mouseSensitivity = 2f;

    [Header("Directional Light")]
    public Transform lightTransform;
    public float lightRotateSpeed = 60f;   // degrees per second

    float _pitch;   // camera vertical look angle
    float _yaw;     // camera horizontal look angle

    void Start()
    {
        // Initialise yaw/pitch from current rotation so the camera doesn't snap on play
        Vector3 angles = transform.eulerAngles;
        _yaw   = angles.y;
        _pitch = angles.x;
    }

    void Update()
    {
        HandleCameraMove();
        HandleMouseLook();
        HandleLightRotation();
    }

    void HandleCameraMove()
    {
        float speed = moveSpeed * (Input.GetKey(KeyCode.LeftShift) ? sprintMult : 1f);

        Vector3 dir = Vector3.zero;
        if (Input.GetKey(KeyCode.W)) dir += transform.forward;
        if (Input.GetKey(KeyCode.S)) dir -= transform.forward;
        if (Input.GetKey(KeyCode.D)) dir += transform.right;
        if (Input.GetKey(KeyCode.A)) dir -= transform.right;
        if (Input.GetKey(KeyCode.E)) dir += Vector3.up;
        if (Input.GetKey(KeyCode.Q)) dir -= Vector3.up;

        transform.position += dir.normalized * speed * Time.deltaTime;
    }

    void HandleMouseLook()
    {
        if (!Input.GetMouseButton(1)) return;   // right mouse button to look

        _yaw   += Input.GetAxis("Mouse X") * mouseSensitivity;
        _pitch -= Input.GetAxis("Mouse Y") * mouseSensitivity;
        _pitch  = Mathf.Clamp(_pitch, -89f, 89f);

        transform.rotation = Quaternion.Euler(_pitch, _yaw, 0f);
    }

    void HandleLightRotation()
    {
        if (lightTransform == null) return;

        float step = lightRotateSpeed * Time.deltaTime;

        // I / K — tilt the light up / down (rotate around its local X axis)
        if (Input.GetKey(KeyCode.I)) lightTransform.Rotate(Vector3.right * -step, Space.World);
        if (Input.GetKey(KeyCode.K)) lightTransform.Rotate(Vector3.right *  step, Space.World);

        // J / L — swing the light left / right (rotate around world Y axis)
        if (Input.GetKey(KeyCode.J)) lightTransform.Rotate(Vector3.up * -step, Space.World);
        if (Input.GetKey(KeyCode.L)) lightTransform.Rotate(Vector3.up *  step, Space.World);
    }
}
