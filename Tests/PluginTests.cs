using System;
using System.IO;
using System.Reflection;
using System.Diagnostics;
using System.Globalization;
namespace BepInEx {
    public class BepInPlugin : Attribute { public BepInPlugin(string a,string b,string c) {} }
    public class BaseUnityPlugin { public bool enabled; public Log Logger = new Log(); }
    public class Log { public void LogInfo(object x) {} public void LogWarning(object x) {} public void LogError(object x) {} }
}
namespace UnityEngine { public class Time { public static float unscaledTime; } }
public class Network {
    public static Network instance = new Network(); public static int calls; public static bool fail;
    public static Network Get() { return instance; }
    public void SimulateUncleanDisconnectFromGameServer() { calls++; if(fail) throw new Exception("test"); }
}
class PluginTests {
    static int checks;
    static void Check(bool value) { if (!value) throw new Exception("Assertion " + checks); checks++; }
    static void Main() {
        string directory = Path.Combine(Path.GetTempPath(), "disconnect-plugin-test-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        try {
            var plugin = new DisconnectOnly.Plugin();
            typeof(DisconnectOnly.Plugin).GetField("directory", BindingFlags.NonPublic|BindingFlags.Instance).SetValue(plugin, directory);
            var flags = BindingFlags.NonPublic|BindingFlags.Instance;
            typeof(DisconnectOnly.Plugin).GetMethod("Awake", flags).Invoke(plugin, null);
            Check(File.Exists(Path.Combine(directory,"heartbeat")));
            var pid = Process.GetCurrentProcess().Id;
            var id = Guid.NewGuid().ToString();
            double now = (DateTime.UtcNow - new DateTime(1970,1,1)).TotalSeconds;
            Action<string> poll = request => {
                File.WriteAllText(Path.Combine(directory,"request"), request);
                UnityEngine.Time.unscaledTime += 1;
                typeof(DisconnectOnly.Plugin).GetMethod("Update", flags).Invoke(plugin,null);
                Check(!File.Exists(Path.Combine(directory,"request")));
            };
            foreach (var request in new [] {id, "bad", id+" "+(pid+1)+" "+(now+4).ToString(CultureInfo.InvariantCulture), id+" "+pid+" "+(now-1).ToString(CultureInfo.InvariantCulture), id+" "+pid+" NaN", id+" "+pid+" Infinity", id+" "+pid+" "+(now+100).ToString(CultureInfo.InvariantCulture)}) {
                poll(request); Check(Network.calls == 0);
            }
            string valid = id+" "+pid+" "+(now+4).ToString(CultureInfo.InvariantCulture);
            poll(valid); Check(Network.calls == 1);
            Check(File.ReadAllText(Path.Combine(directory,"response")) == id+" sent");
            Network.instance = null; poll(valid);
            Check(File.ReadAllText(Path.Combine(directory,"response")) == id+" not-ready");
            Network.instance = new Network(); Network.fail = true; poll(valid);
            Check(File.ReadAllText(Path.Combine(directory,"response")) == id+" error");
            Console.WriteLine("PASS: " + checks + " plugin assertions; no real game API called");
        } finally { Directory.Delete(directory,true); }
    }
}
