using System;
using System.Diagnostics;
using System.IO;
using BepInEx;
using UnityEngine;

namespace DisconnectOnly
{
    [BepInPlugin("local.hearthstone.disconnect-only", "Disconnect Only", "1.0.0")]
    public sealed class Plugin : BaseUnityPlugin
    {
        private readonly string directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Personal),
            "Library", "Application Support", "Hearthstone Disconnect");
        private float nextPoll;
        private float nextHeartbeat;

        private void Awake()
        {
            Directory.CreateDirectory(directory);
            WriteHeartbeat();
            Logger.LogInfo("Disconnect Only ready");
        }

        private void Update()
        {
            float now = Time.unscaledTime;
            if (now >= nextHeartbeat)
            {
                WriteHeartbeat();
                nextHeartbeat = now + 1f;
            }

            if (now < nextPoll) return;
            nextPoll = now + 0.1f;

            string requestPath = Path.Combine(directory, "request");
            if (!File.Exists(requestPath)) return;

            string requestId;
            try
            {
                requestId = File.ReadAllText(requestPath).Trim();
                File.Delete(requestPath);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot read request: " + ex.Message);
                return;
            }

            if (requestId.Length == 0 || requestId.Length > 64) return;

            string result;
            try
            {
                var network = Network.Get();
                if (network == null)
                {
                    result = "not-ready";
                }
                else
                {
                    network.SimulateUncleanDisconnectFromGameServer();
                    result = "sent";
                    Logger.LogInfo("Disconnect requested from desktop app");
                }
            }
            catch (Exception ex)
            {
                result = "error";
                Logger.LogError(ex);
            }

            try
            {
                File.WriteAllText(Path.Combine(directory, "response"), requestId + " " + result);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot write response: " + ex.Message);
            }
        }

        private void WriteHeartbeat()
        {
            try
            {
                string value = Process.GetCurrentProcess().Id + " " +
                    DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                File.WriteAllText(Path.Combine(directory, "heartbeat"), value);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot write heartbeat: " + ex.Message);
            }
        }
    }
}
