using System;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using BepInEx;
using UnityEngine;

namespace DisconnectOnly
{
    [BepInPlugin("local.hearthstone.disconnect-only", "Disconnect Only", "1.1.0")]
    public sealed class Plugin : BaseUnityPlugin
    {
        private readonly string directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Personal),
            "Library", "Application Support", "Hearthstone Disconnect");
        private float nextPoll;
        private float nextHeartbeat;

        private void Awake()
        {
            try {
                Directory.CreateDirectory(directory);
                WriteHeartbeat();
                Logger.LogInfo("Disconnect Only ready (protocol 2)");
            } catch (Exception ex) {
                Logger.LogError("Cannot initialize communication directory: " + ex.Message);
                enabled = false;
            }
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

            // Requests are bound to this process and expire before they can leak
            // into another game/session after a stall or restart.
            string[] fields = requestId.Split((char[])null, StringSplitOptions.RemoveEmptyEntries);
            Guid parsedId;
            int targetPid;
            double expires;
            if (fields.Length != 3 || !Guid.TryParse(fields[0], out parsedId) ||
                !int.TryParse(fields[1], out targetPid) || targetPid != Process.GetCurrentProcess().Id ||
                !double.TryParse(fields[2], NumberStyles.Float, CultureInfo.InvariantCulture, out expires) ||
                double.IsNaN(expires) || double.IsInfinity(expires)) return;
            double nowSeconds = (DateTime.UtcNow - new DateTime(1970, 1, 1)).TotalSeconds;
            if (expires <= nowSeconds || expires > nowSeconds + 10) return;
            requestId = fields[0];

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
                WriteAtomic("response", requestId + " " + result);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot write response: " + ex.Message);
            }
        }

        private void WriteAtomic(string name, string value)
        {
            string destination = Path.Combine(directory, name);
            string temporary = destination + ".tmp";
            try {
                File.WriteAllText(temporary, value);
                if (File.Exists(destination)) File.Replace(temporary, destination, null);
                else File.Move(temporary, destination);
            } finally {
                if (File.Exists(temporary)) File.Delete(temporary);
            }
        }

        private void WriteHeartbeat()
        {
            try
            {
                string value = Process.GetCurrentProcess().Id + " " +
                    DateTimeOffset.UtcNow.ToUnixTimeSeconds() + " 2";
                WriteAtomic("heartbeat", value);
            }
            catch (Exception ex)
            {
                Logger.LogWarning("Cannot write heartbeat: " + ex.Message);
            }
        }
    }
}
