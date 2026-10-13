using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Windows.Forms;

sealed class Session : IDisposable {
    const long Base = 0x140000000;
    public Process Process;
    IntPtr handle;
    public long Clock, Weather;
    public float InitialRate;
    readonly Dictionary<long,byte[]> originals = new Dictionary<long,byte[]>();
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr read);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr h, IntPtr address, byte[] buffer, UIntPtr size, out UIntPtr written);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    public byte[] Read(long address,int size) {
        var bytes=new byte[size]; UIntPtr count;
        if(!ReadProcessMemory(handle,new IntPtr(address),bytes,new UIntPtr((uint)size),out count) || count.ToUInt64()!=(ulong)size)
            throw new InvalidOperationException("Game memory is unavailable. Reconnect after loading into free roam.");
        return bytes;
    }
    long Pointer(long address) {
        long p=BitConverter.ToInt64(Read(address,8),0);
        if(p<0x10000 || p>0x7fffffffffff) throw new InvalidOperationException("Load into free roam, then connect.");
        return p;
    }
    public float Float(long address) { return BitConverter.ToSingle(Read(address,4),0); }
    void Check(long rva, byte[] expected) {
        if(!Read(Base+rva,expected.Length).SequenceEqual(expected)) throw new InvalidOperationException("Unsupported game build or changed hook signature.");
    }
    public Session(Process p) {
        Process=p; handle=OpenProcess(0x438,false,p.Id);
        if(handle==IntPtr.Zero) throw new InvalidOperationException("Cannot open Azimuth. Run both apps at the same privilege level.");
        try {
            Check(0x2959b5,new byte[]{0x48,0x8d,0x1d,0x14,0x9e,0x21,0x03});
            Check(0x2e1520,new byte[]{0x48,0x8b,0x81,0x98,0,0,0,0xc3});
            Check(0x2e1f90,new byte[]{0x48,0x8b,0x81,0x80,4,0,0,0xc3});
            Check(0x2e2e90,new byte[]{0x48,0x8b,0x81,0x88,4,0,0,0xc3});
            Check(0x197b1ac,new byte[]{0x80,0x79,0x24,0});
            var context=Pointer(Pointer(Pointer(Base+0x34aba60)+0x48)+0x98);
            Clock=Pointer(context+0x480); Weather=Pointer(context+0x488);
            Validate(); InitialRate=Float(Clock+0x18);
        } catch { Dispose(); throw; }
    }
    public void Validate() {
        if(Process.HasExited) throw new InvalidOperationException("Azimuth has closed.");
        var context=Pointer(Pointer(Pointer(Base+0x34aba60)+0x48)+0x98);
        if(Pointer(context+0x480)!=Clock || Pointer(context+0x488)!=Weather)
            throw new InvalidOperationException("The world changed. Reconnect in free roam.");
        float seconds=Float(Clock+0x10);
        if(float.IsNaN(seconds)||float.IsInfinity(seconds)||seconds < -1 || seconds > 86401)
            throw new InvalidOperationException("Unexpected clock state; writes disabled.");
        foreach(long off in new long[]{8,0x18,0x5c}) {
            float v=Float(Weather+off);
            if(float.IsNaN(v)||float.IsInfinity(v)||v < -0.01 || v > 1.01)
                throw new InvalidOperationException("Unexpected weather state; writes disabled.");
        }
    }
    public void Write(long address,byte[] bytes,bool restore=true) {
        Validate();
        if(restore && !originals.ContainsKey(address)) originals[address]=Read(address,bytes.Length);
        UIntPtr count;
        if(!WriteProcessMemory(handle,new IntPtr(address),bytes,new UIntPtr((uint)bytes.Length),out count) || count.ToUInt64()!=(ulong)bytes.Length)
            throw new InvalidOperationException("Memory write failed; reconnect before trying again.");
    }
    public void Byte(long a,byte v,bool restore=true) { Write(a,new byte[]{v},restore); }
    public void SetFloat(long a,float v,bool restore=true) { Write(a,BitConverter.GetBytes(v),restore); }
    public void Time(float hours) {
        if(hours<0||hours>=24) throw new ArgumentOutOfRangeException("hours");
        // Native time uses seconds into the day. Keep the interpolation sample in sync.
        SetFloat(Clock+0x10,hours*3600,false);SetFloat(Clock+0xc,hours*3600,false);
        Byte(Clock+0x361,0,false);
    }
    public void Freeze(bool freeze) { Byte(Clock+0x24,freeze?(byte)1:(byte)0); }
    public void SetWeather(float atmosphere,float rain,float environment) {
        foreach(float v in new[]{atmosphere,rain,environment}) if(v<0||v>1) throw new ArgumentOutOfRangeException("weather");
        // Same override flags/current fields used by native setter 0x1981860.
        SetFloat(Weather+0xf4,atmosphere);Byte(Weather+0xf0,1);
        SetFloat(Weather+0x104,rain);Byte(Weather+0x100,1);
        SetFloat(Weather+0xfc,environment);Byte(Weather+0xf8,1);
        SetFloat(Weather+8,atmosphere);SetFloat(Weather+0x10,0);
        SetFloat(Weather+0x5c,rain);SetFloat(Weather+0x18,environment);
    }
    public void Restore() {
        Validate();
        foreach(var item in originals.ToArray()) Write(item.Key,item.Value,false);
        originals.Clear();
    }
    public void Dispose() { if(handle!=IntPtr.Zero) {CloseHandle(handle);handle=IntPtr.Zero;} }
}

sealed class Menu : Form {
    Session session;
    readonly Label status=new Label(), live=new Label();
    readonly NumericUpDown hour=new NumericUpDown();
    readonly CheckBox freeze=new CheckBox(), holdWeather=new CheckBox();
    readonly TrackBar atmosphere=new TrackBar(), rain=new TrackBar(), environment=new TrackBar();
    readonly Timer timer=new Timer();
    bool updating;
    string lastState="Start Azimuth and enter free roam, then Connect.";
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr hwnd,int id,uint modifiers,uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr hwnd,int id);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd,int index);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hwnd,uint message,IntPtr wparam,IntPtr lparam);
    protected override bool ShowWithoutActivation { get { return true; } }
    protected override CreateParams CreateParams {
        get { var cp=base.CreateParams;cp.ExStyle|=0x08000000;return cp; } // WS_EX_NOACTIVATE
    }
    public Menu() {
        Text="FH2 · Time & Weather (experimental)"; ClientSize=new Size(460,510);
        FormBorderStyle=FormBorderStyle.FixedSingle;MaximizeBox=false;TopMost=true;
        BackColor=Color.FromArgb(23,25,31);ForeColor=Color.White;Font=new Font("Segoe UI",10);
        StartPosition=FormStartPosition.CenterScreen;
        AddLabel("TIME & WEATHER",20,16,420,30,16);
        AddLabel("F6: show / hide · mouse controls keep game focus",20,51,420,22,9);
        Button("Connect",20,84,130,Connect);
        Button("Restore / release",160,84,155,Release);
        live.SetBounds(20,127,420,25);live.Text="Disconnected";Controls.Add(live);
        AddLabel("Time (24-hour)",20,168,140,24,10);
        hour.SetBounds(170,166,105,28);hour.ForeColor=Color.Black;hour.BackColor=Color.White;hour.Minimum=0;hour.Maximum=23.99m;hour.DecimalPlaces=2;hour.Increment=.25m;hour.Value=12;Controls.Add(hour);
        Button("Set time",290,165,120,()=>Run(()=>session.Time((float)hour.Value)));
        freeze.SetBounds(20,204,400,24);freeze.Text="Freeze time";Controls.Add(freeze);
        freeze.CheckedChanged+=(s,e)=>{if(!updating)Run(()=>session.Freeze(freeze.Checked));};
        Button("Dawn",20,238,90,()=>SetHour(6)); Button("Noon",120,238,90,()=>SetHour(12));
        Button("Sunset",220,238,90,()=>SetHour(19));Button("Midnight",320,238,100,()=>SetHour(0));
        Slider("Atmosphere",atmosphere,278);Slider("Rain",rain,321);Slider("Environment",environment,364);
        holdWeather.SetBounds(20,411,410,24);holdWeather.Text="Hold weather override (live)";Controls.Add(holdWeather);
        holdWeather.CheckedChanged+=(s,e)=>{if(!updating && holdWeather.Checked)ApplyWeather();};
        Button("Clear",20,442,90,()=>Preset(0,0,0));Button("Rain",120,442,90,()=>Preset(70,80,80));
        Button("Apply",220,442,90,ApplyWeather);
        status.SetBounds(20,478,420,30);status.Font=new Font("Segoe UI",8);status.Text=lastState;Controls.Add(status);
        timer.Interval=200;timer.Tick+=(s,e)=>Tick();timer.Start();
        Shown+=(s,e)=>{if(!RegisterHotKey(Handle,1,0x4000,0x75))status.Text="F6 is in use; switch to this window with Alt+Tab.";};
        FormClosing+=(s,e)=>{timer.Stop();try{if(session!=null)session.Restore();}catch{} if(session!=null)session.Dispose();UnregisterHotKey(Handle,1);};
    }
    void AddLabel(string text,int x,int y,int width,int height,int size) {
        var label=new Label{Text=text,Font=new Font("Segoe UI",size,size>=16?FontStyle.Bold:FontStyle.Regular)};
        label.SetBounds(x,y,width,height);Controls.Add(label);
    }
    void Button(string text,int x,int y,int width,Action action) {
        var button=new Button{Text=text,FlatStyle=FlatStyle.Flat,BackColor=Color.FromArgb(45,49,60),ForeColor=Color.White};
        button.SetBounds(x,y,width,30);button.Click+=(s,e)=>action();Controls.Add(button);
    }
    void Slider(string text,TrackBar bar,int y) {
        AddLabel(text,20,y,130,25,10);bar.SetBounds(150,y-6,270,38);bar.Minimum=0;bar.Maximum=100;bar.TickFrequency=25;
        Controls.Add(bar);bar.Scroll+=(s,e)=>{if(holdWeather.Checked)ApplyWeather();};
    }
    void Connect() {
        try {
            if(session!=null) {try{session.Restore();}catch{} session.Dispose();session=null;}
            var processes=Process.GetProcessesByName("azimuth").Concat(Process.GetProcessesByName("azimuth-gt500-test")).ToArray();
            if(processes.Length!=1)throw new InvalidOperationException("Start exactly one Azimuth session and enter free roam.");
            session=new Session(processes[0]);updating=true;
            hour.Value=Math.Min(23.99m,Math.Max(0,(decimal)(session.Float(session.Clock+0x10)/3600)));
            freeze.Checked=session.Read(session.Clock+0x24,1)[0]!=0;holdWeather.Checked=false;
            atmosphere.Value=(int)(session.Float(session.Weather+8)*100);rain.Value=(int)(session.Float(session.Weather+0x5c)*100);environment.Value=(int)(session.Float(session.Weather+0x18)*100);
            updating=false;lastState="Connected. Changes affect this running session.";status.Text=lastState;
        }catch(Exception e){updating=false;status.Text=e.Message;if(session!=null){session.Dispose();session=null;}}
    }
    void Run(Action action) {
        if(session==null){status.Text="Connect after entering free roam.";return;}
        try {action();status.Text="Applied. Check the game; rendering test is pending.";}
        catch(Exception e){status.Text=e.Message;updating=true;holdWeather.Checked=false;freeze.Checked=false;updating=false;}
    }
    void SetHour(decimal value){hour.Value=value;Run(()=>session.Time((float)value));}
    void ApplyWeather(){Run(()=>session.SetWeather(atmosphere.Value/100f,rain.Value/100f,environment.Value/100f));}
    void Preset(int a,int r,int e){atmosphere.Value=a;rain.Value=r;environment.Value=e;updating=true;holdWeather.Checked=true;updating=false;ApplyWeather();}
    void Release(){Run(()=>session.Restore());updating=true;freeze.Checked=false;holdWeather.Checked=false;updating=false;}
    void Tick(){
        if(session==null)return;
        try{
            session.Validate();
            if(holdWeather.Checked)session.SetWeather(atmosphere.Value/100f,rain.Value/100f,environment.Value/100f);
            float seconds=session.Float(session.Clock+0x10);int hours=(int)(seconds/3600),minutes=(int)(seconds%3600/60);
            live.Text=String.Format("Connected · PID {0} · {1:00}:{2:00}",session.Process.Id,hours,minutes);
        }catch(Exception e){live.Text="Disconnected";status.Text=e.Message;session.Dispose();session=null;}
    }
    protected override void WndProc(ref Message m){
        if(m.Msg==0x21){m.Result=new IntPtr(3);return;} // WM_MOUSEACTIVATE -> MA_NOACTIVATE; keep the click
        if(m.Msg==0x312){if(Visible)Hide();else Show();return;} // F6 never activates the menu
        base.WndProc(ref m);
    }
    [STAThread] static void Main(string[] args){
        Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
        using(var menu=new Menu()){
            if(args.Contains("--focus-test")){
                var before=GetForegroundWindow();menu.Show();Application.DoEvents();
                var shown=GetForegroundWindow();
                bool style=(GetWindowLongPtr(menu.Handle,-20).ToInt64()&0x08000000)!=0;
                long mouse=SendMessage(menu.Handle,0x21,IntPtr.Zero,new IntPtr(0x02010001)).ToInt64();
                // Exercise the child-button mouse path as well as the top-level activation message.
                var connectButton=menu.Controls.OfType<Button>().First(b=>b.Text=="Connect");
                SendMessage(connectButton.Handle,0x201,new IntPtr(1),new IntPtr(0x000a000a));
                SendMessage(connectButton.Handle,0x202,IntPtr.Zero,new IntPtr(0x000a000a));Application.DoEvents();
                bool clickUnchanged=GetForegroundWindow()==before;
                SendMessage(menu.Handle,0x312,new IntPtr(1),IntPtr.Zero);Application.DoEvents();
                SendMessage(menu.Handle,0x312,new IntPtr(1),IntPtr.Zero);Application.DoEvents();
                bool unchanged=GetForegroundWindow()==before && shown==before && clickUnchanged;
                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"focus-test.txt"),
                    String.Format("{0}\r\nWS_EX_NOACTIVATE={1}\r\nMouse activation result={2} (3 means accept click without activation)\r\nShowing and F6 hide/show preserve foreground={3}\r\nForeground before=0x{4:x}; after=0x{5:x}\r\n",style&&mouse==3&&unchanged?"PASS":"FAIL",style,mouse,unchanged,before.ToInt64(),GetForegroundWindow().ToInt64()));return;
            }
            if(args.Contains("--self-test")){
                string result;
                Session test=null;
                try {
                    var processes=Process.GetProcessesByName("azimuth").ToArray();
                    if(processes.Length!=1)throw new InvalidOperationException("Exactly one running Azimuth is required.");
                    test=new Session(processes[0]);
                    byte freezeBefore=test.Read(test.Clock+0x24,1)[0];
                    byte[] flagsBefore=new[]{test.Read(test.Weather+0xf0,1)[0],test.Read(test.Weather+0xf8,1)[0],test.Read(test.Weather+0x100,1)[0]};
                    float a=test.Float(test.Weather+8),r=test.Float(test.Weather+0x5c),e=test.Float(test.Weather+0x18);
                    test.Freeze(true);
                    float clockBefore=test.Float(test.Clock+0x10);
                    System.Threading.Thread.Sleep(250);
                    float clockAfter=test.Float(test.Clock+0x10);
                    if(test.Read(test.Clock+0x24,1)[0]!=1)throw new Exception("Freeze flag did not persist.");
                    test.SetWeather(a,r,e);
                    if(test.Read(test.Weather+0xf0,1)[0]!=1 || test.Read(test.Weather+0xf8,1)[0]!=1 || test.Read(test.Weather+0x100,1)[0]!=1)throw new Exception("Weather override readback failed.");
                    test.Restore();
                    if(test.Read(test.Clock+0x24,1)[0]!=freezeBefore)throw new Exception("Freeze restoration failed.");
                    if(!new[]{test.Read(test.Weather+0xf0,1)[0],test.Read(test.Weather+0xf8,1)[0],test.Read(test.Weather+0x100,1)[0]}.SequenceEqual(flagsBefore))throw new Exception("Weather flag restoration failed.");
                    result=String.Format("PASS: live signatures and manager pointers validated. PID={0}\r\nFreeze flag write/read/restore passed. Clock delta over 250ms={1}\r\nWeather override write/read/restore passed, using existing intensities.\r\nVisible time/weather changes still need an in-game test.\r\n",test.Process.Id,clockAfter-clockBefore);
                }catch(Exception ex){result="FAILED: "+ex.Message;}
                finally {if(test!=null){try{test.Restore();}catch{}test.Dispose();}}
                File.WriteAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"self-test.txt"),result);return;
            }
            if(args.Contains("--preview")){menu.Show();Application.DoEvents();using(var bitmap=new Bitmap(menu.Width,menu.Height)){menu.DrawToBitmap(bitmap,new Rectangle(0,0,bitmap.Width,bitmap.Height));bitmap.Save(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"preview.png"));}return;}
            Application.Run(menu);
        }
    }
}
