// Espelhô - jogue o celular Android na tela do PC.
// Interface nativa do Windows (WinForms). Compatível com o compilador do .NET Framework 4 (C# 5).
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Espelhô")]
[assembly: AssemblyProduct("Espelhô")]
[assembly: AssemblyDescription("Jogue o celular Android na tela do PC")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace EspelhoApp
{
    enum UiState { Init, Download, NoDevice, Allow, Ready, Play, Error }

    static class Program
    {
        [DllImport("user32.dll")]
        static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            bool created;
            using (Mutex mutex = new Mutex(true, "Espelho.App.SingleInstance", out created))
            {
                if (!created) return;
                try { SetProcessDPIAware(); } catch (Exception) { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch (Exception) { }
                try
                {
                    Application.Run(new MainForm());
                }
                catch (Exception ex)
                {
                    MessageBox.Show("Ocorreu um erro inesperado:\n\n" + ex.Message, "Espelhô");
                }
            }
        }
    }

    // ------------------------------------------------------------------ tema e desenho
    static class Theme
    {
        public static readonly Color Bg = ColorTranslator.FromHtml("#12141C");
        public static readonly Color Card = ColorTranslator.FromHtml("#1C2030");
        public static readonly Color Line = ColorTranslator.FromHtml("#2B3048");
        public static readonly Color Text = ColorTranslator.FromHtml("#F2F4FA");
        public static readonly Color Muted = ColorTranslator.FromHtml("#9AA3BC");
        public static readonly Color Accent = ColorTranslator.FromHtml("#7C5CFF");
        public static readonly Color Field = ColorTranslator.FromHtml("#262B40");
        public static readonly Color Green = ColorTranslator.FromHtml("#22C55E");
    }

    static class Gfx
    {
        public static GraphicsPath Round(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            int d = Math.Max(2, rad * 2);
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        public static StringFormat Center()
        {
            StringFormat f = new StringFormat();
            f.Alignment = StringAlignment.Center;
            f.LineAlignment = StringAlignment.Center;
            f.Trimming = StringTrimming.EllipsisCharacter;
            f.FormatFlags = StringFormatFlags.NoWrap;
            return f;
        }
    }

    // Cartão arredondado
    class Card : Panel
    {
        public Card()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            BackColor = Theme.Bg;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Theme.Bg);
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width - 1, Height - 1), 16))
            {
                using (SolidBrush b = new SolidBrush(Theme.Card)) { g.FillPath(b, p); }
                using (Pen pen = new Pen(Theme.Line, 1f)) { g.DrawPath(pen, p); }
            }
        }
    }

    // Botão arredondado
    class RButton : Control
    {
        bool hover;
        bool down;
        Color fill = Theme.Card;
        Color fillHover = Theme.Field;
        Color fillDown = Theme.Line;
        Color textColor = Theme.Text;
        public int Radius = 12;
        public Color Backdrop = Theme.Bg;

        public RButton()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
        }

        public void Style(Color f, Color fh, Color fd, Color t)
        {
            fill = f; fillHover = fh; fillDown = fd; textColor = t;
            Invalidate();
        }

        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Backdrop);
            Color f = fill;
            Color t = textColor;
            if (!Enabled) { f = Theme.Card; t = Color.FromArgb(110, Theme.Muted); }
            else if (down) f = fillDown;
            else if (hover) f = fillHover;
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width - 1, Height - 1), Radius))
            {
                using (SolidBrush b = new SolidBrush(f)) { g.FillPath(b, p); }
            }
            using (StringFormat sf = Gfx.Center())
            using (SolidBrush tb = new SolidBrush(t))
            {
                g.DrawString(Text, Font, tb, new RectangleF(4, 0, Width - 8, Height), sf);
            }
        }
    }

    // Caixa de seleção escura
    class Check : Control
    {
        bool chk;
        public event EventHandler CheckedChanged;
        public Color Backdrop = Theme.Card;

        public Check()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
        }

        public bool Checked
        {
            get { return chk; }
            set
            {
                if (chk == value) return;
                chk = value;
                Invalidate();
                if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
            }
        }

        protected override void OnClick(EventArgs e)
        {
            Checked = !Checked;
            base.OnClick(e);
        }
        protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Backdrop);
            int s = 18;
            int y = (Height - s) / 2;
            Color boxFill = chk ? Theme.Accent : Theme.Field;
            Color textCol = Enabled ? Theme.Text : Color.FromArgb(120, Theme.Muted);
            if (!Enabled) boxFill = Theme.Line;
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, y, s, s), 5))
            {
                using (SolidBrush b = new SolidBrush(boxFill)) { g.FillPath(b, p); }
                if (!chk)
                {
                    using (Pen pen = new Pen(Theme.Muted, 1f)) { g.DrawPath(pen, p); }
                }
            }
            if (chk)
            {
                using (Pen pen = new Pen(Color.White, 2.2f))
                {
                    pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                    g.DrawLine(pen, 4f, y + 9.5f, 7.5f, y + 13f);
                    g.DrawLine(pen, 7.5f, y + 13f, 14f, y + 5f);
                }
            }
            using (StringFormat sf = new StringFormat())
            using (SolidBrush tb = new SolidBrush(textCol))
            {
                sf.LineAlignment = StringAlignment.Center;
                sf.Trimming = StringTrimming.EllipsisCharacter;
                sf.FormatFlags = StringFormatFlags.NoWrap;
                g.DrawString(Text, Font, tb, new RectangleF(s + 8, 0, Width - s - 8, Height), sf);
            }
        }
    }

    // Lista suspensa escura
    class DarkCombo : ComboBox
    {
        public DarkCombo()
        {
            DropDownStyle = ComboBoxStyle.DropDownList;
            FlatStyle = FlatStyle.Flat;
            DrawMode = DrawMode.OwnerDrawFixed;
            ItemHeight = 24;
            BackColor = Theme.Field;
            ForeColor = Theme.Text;
        }

        protected override void OnDrawItem(DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            bool inEdit = (e.State & DrawItemState.ComboBoxEdit) != 0;
            bool sel = ((e.State & DrawItemState.Selected) != 0) && !inEdit;
            using (SolidBrush b = new SolidBrush(sel ? Theme.Accent : Theme.Field))
            {
                e.Graphics.FillRectangle(b, e.Bounds);
            }
            Rectangle r = e.Bounds;
            r.X += 8; r.Width -= 8;
            TextRenderer.DrawText(e.Graphics, GetItemText(Items[e.Index]), Font, r, Theme.Text,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
        }
    }

    // Ícone grande do cartão de status
    class StatusIcon : Control
    {
        public UiState State = UiState.Init;
        public Color Col = Theme.Accent;

        public StatusIcon()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Theme.Card);
            int w = Width;
            int h = Height;
            int pw = (int)(w * 0.52);
            int ph = (int)(h * 0.94);
            int rx = (w - pw) / 2;
            int ry = (h - ph) / 2;
            float cx = w / 2f;
            float cy = h / 2f;
            using (Pen pen = new Pen(Col, 3f))
            {
                pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round; pen.LineJoin = LineJoin.Round;
                using (GraphicsPath p = Gfx.Round(new Rectangle(rx, ry, pw, ph), 10)) { g.DrawPath(pen, p); }
                g.DrawLine(pen, cx - 6, ry + 8, cx + 6, ry + 8);
            }
            using (Pen pen4 = new Pen(Col, 4f))
            using (SolidBrush br = new SolidBrush(Col))
            {
                pen4.StartCap = LineCap.Round; pen4.EndCap = LineCap.Round; pen4.LineJoin = LineJoin.Round;
                switch (State)
                {
                    case UiState.Ready:
                        g.DrawLine(pen4, cx - 9, cy + 2, cx - 2, cy + 9);
                        g.DrawLine(pen4, cx - 2, cy + 9, cx + 10, cy - 7);
                        break;
                    case UiState.Play:
                        g.FillPolygon(br, new PointF[] {
                            new PointF(cx - 6, cy - 11), new PointF(cx - 6, cy + 11), new PointF(cx + 10, cy) });
                        break;
                    case UiState.Allow:
                    case UiState.Error:
                        g.DrawLine(pen4, cx, cy - 12, cx, cy + 3);
                        g.FillEllipse(br, cx - 3, cy + 9, 6f, 6f);
                        break;
                    case UiState.Download:
                        g.DrawLine(pen4, cx, cy - 11, cx, cy + 8);
                        g.DrawLine(pen4, cx - 8, cy + 1, cx, cy + 9);
                        g.DrawLine(pen4, cx + 8, cy + 1, cx, cy + 9);
                        break;
                    default:
                        foreach (int dx in new int[] { -12, -3, 6 })
                        {
                            g.FillEllipse(br, cx + dx, cy - 3, 6f, 6f);
                        }
                        break;
                }
            }
        }
    }

    // Barra de progresso
    class Bar : Control
    {
        double val = -1;

        public Bar()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }

        public double Value
        {
            get { return val; }
            set { val = value; Invalidate(); }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(Theme.Card);
            int w = Width - 1;
            int h = Height - 1;
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, w, h), 4))
            using (SolidBrush b = new SolidBrush(Theme.Line))
            {
                g.FillPath(b, p);
            }
            if (val > 0)
            {
                int fw = (int)Math.Max(8, w * Math.Min(1.0, val));
                using (GraphicsPath p2 = Gfx.Round(new Rectangle(0, 0, fw, h), 4))
                using (SolidBrush b2 = new SolidBrush(Theme.Accent))
                {
                    g.FillPath(b2, p2);
                }
            }
        }
    }

    // Número dentro de um círculo (tela de ajuda)
    class Badge : Control
    {
        public Badge()
        {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            g.Clear(Theme.Bg);
            using (SolidBrush b = new SolidBrush(Theme.Accent)) { g.FillEllipse(b, 0, 0, Width - 1, Height - 1); }
            using (StringFormat sf = Gfx.Center())
            using (Font f = new Font("Segoe UI", 11f, FontStyle.Bold))
            {
                g.DrawString(Text, f, Brushes.White, new RectangleF(0, 0, Width, Height), sf);
            }
        }
    }

    class AppItem
    {
        public string Label;
        public string Pkg;
    }

    // ------------------------------------------------------------------ processos
    static class Proc
    {
        // Roda um programa e devolve a saída (normal + erros) como texto. Tem limite de tempo.
        public static string Run(string file, string args, int timeoutMs, string workDir)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(file, args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.StandardOutputEncoding = Encoding.UTF8;
                psi.StandardErrorEncoding = Encoding.UTF8;
                if (workDir != null) psi.WorkingDirectory = workDir;
                StringBuilder sb = new StringBuilder();
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    DataReceivedEventHandler h = delegate(object sender, DataReceivedEventArgs ev)
                    {
                        if (ev.Data != null) { lock (sb) { sb.AppendLine(ev.Data); } }
                    };
                    p.OutputDataReceived += h;
                    p.ErrorDataReceived += h;
                    p.Start();
                    p.BeginOutputReadLine();
                    p.BeginErrorReadLine();
                    if (!p.WaitForExit(timeoutMs))
                    {
                        try { p.Kill(); } catch (Exception) { }
                    }
                    Thread.Sleep(80);
                    lock (sb) { return sb.ToString(); }
                }
            }
            catch (Exception)
            {
                return "";
            }
        }

        // Guarda a saída binária de um programa em um arquivo (usado nas capturas de tela).
        public static bool RunToFile(string file, string args, string outPath, int timeoutMs)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(file, args);
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs ev) { };
                    p.Start();
                    p.BeginErrorReadLine();
                    using (FileStream fs = File.Create(outPath))
                    {
                        Stream source = p.StandardOutput.BaseStream;
                        Thread copier = new Thread(delegate()
                        {
                            try { source.CopyTo(fs); } catch (Exception) { }
                        });
                        copier.IsBackground = true;
                        copier.Start();
                        if (!copier.Join(timeoutMs))
                        {
                            try { p.Kill(); } catch (Exception) { }
                            copier.Join(2000);
                            return false;
                        }
                    }
                    p.WaitForExit(3000);
                    return true;
                }
            }
            catch (Exception)
            {
                return false;
            }
        }

        public static void StartAdbServer(string adb)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(adb, "start-server");
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                using (Process p = Process.Start(psi)) { p.WaitForExit(10000); }
            }
            catch (Exception) { }
        }

        public static string LastLine(string text)
        {
            string result = "";
            foreach (string line in text.Split('\n'))
            {
                string l = line.Trim();
                if (l.Length > 0 && !l.StartsWith("*")) result = l;
            }
            return result;
        }
    }

    // ------------------------------------------------------------------ ajuda
    class HelpForm : Form
    {
        public HelpForm()
        {
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(440, 560);
            Text = "Como ativar a Depuração USB";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            BackColor = Theme.Bg;
            ForeColor = Theme.Text;
            Font = new Font("Segoe UI", 10f);

            Controls.Add(MainForm.MakeLabel("Ativar a Depuração USB", 24, 20, 392, 36, 17f, true, Theme.Text, Theme.Bg));
            Controls.Add(MainForm.MakeLabel("Você só precisa fazer isso uma vez, no celular Android.", 26, 58, 392, 24, 10f, false, Theme.Muted, Theme.Bg));

            string[] steps = new string[] {
                "Abra Configurações › Sobre o telefone.",
                "Toque 7 vezes em \"Número da versão\". Pode pedir sua senha ou PIN.",
                "Volte e abra \"Opções do desenvolvedor\" (fica em Sistema ou no fim da lista).",
                "Ative a chave \"Depuração USB\".",
                "Ligue o cabo USB no PC e toque em Permitir quando o celular perguntar."
            };
            int y = 90;
            for (int i = 0; i < steps.Length; i++)
            {
                Badge b = new Badge();
                b.Text = (i + 1).ToString();
                b.Location = new Point(24, y);
                b.Size = new Size(32, 32);
                Controls.Add(b);
                Controls.Add(MainForm.MakeLabel(steps[i], 72, y - 2, 350, 52, 10.5f, false, Theme.Text, Theme.Bg));
                y += 62;
            }
            Controls.Add(MainForm.MakeLabel(
                "Dicas: use um cabo que transfira dados (alguns só carregam). Em celulares Xiaomi, Redmi e Poco, ative também \"Depuração USB (Configurações de segurança)\" nas Opções do desenvolvedor, senão os toques podem falhar ou demorar.",
                26, y + 4, 392, 76, 9f, false, Theme.Muted, Theme.Bg));

            RButton ok = new RButton();
            ok.Text = "Entendi";
            ok.Font = new Font("Segoe UI", 11f, FontStyle.Bold);
            ok.Location = new Point(24, 496);
            ok.Size = new Size(392, 46);
            ok.Style(Theme.Accent, ColorTranslator.FromHtml("#8F74FF"), ColorTranslator.FromHtml("#6A49F0"), Color.White);
            ok.Click += delegate(object sender, EventArgs ev) { Close(); };
            Controls.Add(ok);
        }
    }

    // ------------------------------------------------------------------ janela principal
    class MainForm : Form
    {
        static readonly string[] QualityNames = new string[] {
            "Leve (computador mais fraco)", "Equilibrada (recomendada)", "Máxima (mais nítida)" };
        static readonly string[] QualityArgs = new string[] {
            "-m 960 -b 4M", "-m 1280 -b 8M", "-b 16M" };
        const string NoApp = "Não abrir nada (eu abro no celular)";

        // caminhos
        string baseDir, progDir, scrcpyExe, adbExe, cfgFile;

        // controles
        StatusIcon statusIcon;
        Label titleLabel, descLabel;
        Bar bar;
        DarkCombo appCombo, qualityCombo;
        RButton btnRefApps, btnPlay, btnRec, btnShot, btnFolder, btnWifi, btnShort, btnHelp;
        Check chkFull, chkOff, chkPad, chkAudio, chkTouch, chkShow;
        System.Windows.Forms.Timer timer, flashTimer;
        ToolTip tip = new ToolTip();

        // estado
        UiState uiState = UiState.Init;
        string stateKey = "";
        string serial;
        string phoneName;
        bool wireless;
        bool busy;
        bool polling;
        bool featHover, featStartApp, featGamepad;
        List<string> appPkgs = new List<string>();
        bool appsLoaded;
        bool appsLoading;
        string appsFor;
        bool rec;
        string recFile;
        Process game;
        StringBuilder gameLog;
        Dictionary<string, string> cfg = new Dictionary<string, string>();

        public MainForm()
        {
            SetupPaths();
            LoadConfig();

            SuspendLayout();
            AutoScaleDimensions = new SizeF(96F, 96F);
            AutoScaleMode = AutoScaleMode.Dpi;
            ClientSize = new Size(460, 646);
            Text = "Espelhô";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            BackColor = Theme.Bg;
            ForeColor = Theme.Text;
            Font = new Font("Segoe UI", 10f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch (Exception) { }
            tip.InitialDelay = 400;
            tip.AutoPopDelay = 9000;

            Panel accent = new Panel();
            accent.Dock = DockStyle.Top;
            accent.Height = 5;
            accent.BackColor = Theme.Accent;

            Label head = MakeLabel("Espelhô", 24, 12, 412, 40, 20f, true, Theme.Text, Theme.Bg);
            Label sub = MakeLabel("Seu celular na tela do PC. Conecte, escolha o jogo e jogue.", 26, 52, 412, 22, 10f, false, Theme.Muted, Theme.Bg);

            // cartão de status
            Card cardStatus = new Card();
            cardStatus.Location = new Point(20, 84);
            cardStatus.Size = new Size(420, 128);
            statusIcon = new StatusIcon();
            statusIcon.Location = new Point(20, 14);
            statusIcon.Size = new Size(70, 92);
            titleLabel = MakeLabel("", 108, 18, 296, 30, 14f, true, Theme.Text, Theme.Card);
            descLabel = MakeLabel("", 108, 52, 298, 62, 9.5f, false, Theme.Muted, Theme.Card);
            bar = new Bar();
            bar.Location = new Point(20, 112);
            bar.Size = new Size(380, 8);
            bar.Visible = false;
            cardStatus.Controls.Add(statusIcon);
            cardStatus.Controls.Add(titleLabel);
            cardStatus.Controls.Add(descLabel);
            cardStatus.Controls.Add(bar);

            // escolha do jogo
            Label lblGame = MakeLabel("Jogo para abrir sozinho", 24, 220, 300, 20, 9f, false, Theme.Muted, Theme.Bg);
            appCombo = new DarkCombo();
            appCombo.Location = new Point(20, 242);
            appCombo.Size = new Size(376, 28);
            appCombo.MaxDropDownItems = 12;
            appCombo.Items.Add(NoApp);
            appCombo.SelectedIndex = 0;
            appPkgs.Add(null);
            btnRefApps = new RButton();
            btnRefApps.Text = "↻";
            btnRefApps.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
            btnRefApps.Location = new Point(404, 241);
            btnRefApps.Size = new Size(36, 30);
            btnRefApps.Radius = 8;
            btnRefApps.Style(Theme.Field, Theme.Line, Theme.Line, Theme.Text);
            btnRefApps.Click += delegate(object sender, EventArgs ev) { appsFor = null; BeginApps(); };

            // botão jogar
            btnPlay = new RButton();
            btnPlay.Location = new Point(20, 286);
            btnPlay.Size = new Size(420, 60);
            btnPlay.Radius = 14;
            btnPlay.Font = new Font("Segoe UI", 15f, FontStyle.Bold);
            btnPlay.Click += delegate(object sender, EventArgs ev) { OnPlayClick(); };

            // gravar, capturar, pasta
            btnRec = MakeSecBtn("●  Gravar", 20, 358);
            btnShot = MakeSecBtn("Capturar tela", 162, 358);
            btnFolder = MakeSecBtn("Abrir pasta Jogos", 304, 358);
            btnRec.Click += delegate(object sender, EventArgs ev) { ToggleRec(); };
            btnShot.Click += delegate(object sender, EventArgs ev) { TakeShot(); };
            btnFolder.Click += delegate(object sender, EventArgs ev) { OpenGamesFolder(); };

            // configurações
            Card cardCfg = new Card();
            cardCfg.Location = new Point(20, 408);
            cardCfg.Size = new Size(420, 176);
            Label lblCfg = MakeLabel("Configurações", 20, 12, 300, 26, 12f, true, Theme.Text, Theme.Card);
            Label lblQ = MakeLabel("Qualidade", 20, 48, 100, 24, 10f, false, Theme.Muted, Theme.Card);
            qualityCombo = new DarkCombo();
            qualityCombo.Location = new Point(120, 44);
            qualityCombo.Size = new Size(280, 28);
            foreach (string q in QualityNames) qualityCombo.Items.Add(q);
            int qi = CfgInt("quality", 1);
            if (qi < 0 || qi >= QualityNames.Length) qi = 1;
            qualityCombo.SelectedIndex = qi;
            chkFull = MakeCheck("Tela cheia", 20, 84, 196, CfgBool("fullscreen", false));
            chkOff = MakeCheck("Apagar tela do celular", 20, 112, 196, CfgBool("screenoff", false));
            chkPad = MakeCheck("Usar controle", 20, 140, 196, CfgBool("pad", false));
            chkAudio = MakeCheck("Som no computador", 222, 84, 190, CfgBool("audio", true));
            chkTouch = MakeCheck("Toque mais preciso", 222, 112, 190, CfgBool("touch", true));
            chkShow = MakeCheck("Mostrar toques", 222, 140, 190, CfgBool("showtouches", false));
            cardCfg.Controls.Add(lblCfg);
            cardCfg.Controls.Add(lblQ);
            cardCfg.Controls.Add(qualityCombo);
            cardCfg.Controls.Add(chkFull);
            cardCfg.Controls.Add(chkOff);
            cardCfg.Controls.Add(chkPad);
            cardCfg.Controls.Add(chkAudio);
            cardCfg.Controls.Add(chkTouch);
            cardCfg.Controls.Add(chkShow);

            // botões de baixo
            btnWifi = MakeSecBtn("Sem cabo (Wi-Fi)", 20, 598);
            btnShort = MakeSecBtn("Criar atalho", 162, 598);
            btnHelp = MakeSecBtn("Ajuda", 304, 598);
            btnWifi.Click += delegate(object sender, EventArgs ev) { ConnectWifi(); };
            btnShort.Click += delegate(object sender, EventArgs ev) { CreateShortcut(); };
            btnHelp.Click += delegate(object sender, EventArgs ev) { using (HelpForm hf = new HelpForm()) { hf.ShowDialog(this); } };

            Controls.Add(accent);
            Controls.Add(head);
            Controls.Add(sub);
            Controls.Add(cardStatus);
            Controls.Add(lblGame);
            Controls.Add(appCombo);
            Controls.Add(btnRefApps);
            Controls.Add(btnPlay);
            Controls.Add(btnRec);
            Controls.Add(btnShot);
            Controls.Add(btnFolder);
            Controls.Add(cardCfg);
            Controls.Add(btnWifi);
            Controls.Add(btnShort);
            Controls.Add(btnHelp);

            tip.SetToolTip(appCombo, "Escolha o jogo: ele abre sozinho no celular quando você clica em JOGAR.");
            tip.SetToolTip(btnRefApps, "Atualizar a lista de jogos do celular");
            tip.SetToolTip(btnRec, "Liga a gravação. Ela começa ao clicar em JOGAR e termina ao fechar a janela do jogo. Se clicar durante o jogo, a imagem pisca por um instante.");
            tip.SetToolTip(btnShot, "Tira uma foto da tela do celular e salva na pasta Jogos da Área de Trabalho.");
            tip.SetToolTip(btnFolder, "Abre a pasta Jogos, onde ficam as gravações e capturas.");
            tip.SetToolTip(chkOff, "Deixe desmarcado se alguém for tocar na tela do celular.");
            tip.SetToolTip(chkPad, "Ligue o controle no PC (USB ou Bluetooth) antes de jogar. O jogo precisa aceitar controle.");
            tip.SetToolTip(chkTouch, "Evita que o simples movimento do mouse atrapalhe os toques.");
            tip.SetToolTip(chkShow, "Mostra um ponto na tela onde alguém toca. Ajuda quem está só assistindo.");
            tip.SetToolTip(btnWifi, "Conecta por Wi-Fi para você poder tirar o cabo USB.");
            tip.SetToolTip(btnShort, "Cria um atalho com ícone na Área de Trabalho.");
            ResumeLayout(false);

            timer = new System.Windows.Forms.Timer();
            timer.Interval = 1500;
            timer.Tick += delegate(object sender, EventArgs ev) { PollTick(); };
            flashTimer = new System.Windows.Forms.Timer();
            flashTimer.Interval = 1800;
            flashTimer.Tick += delegate(object sender, EventArgs ev)
            {
                flashTimer.Stop();
                btnShot.Text = "Capturar tela";
            };

            UpdateButtons();
            Shown += delegate(object sender, EventArgs ev) { Prepare(); };
        }

        // ---------------------------------------------------------- criação de controles
        public static Label MakeLabel(string text, int x, int y, int w, int h, float size, bool bold, Color color, Color back)
        {
            Label l = new Label();
            l.AutoSize = false;
            l.Text = text;
            l.Location = new Point(x, y);
            l.Size = new Size(w, h);
            l.Font = new Font("Segoe UI", size, bold ? FontStyle.Bold : FontStyle.Regular);
            l.ForeColor = color;
            l.BackColor = back;
            return l;
        }

        RButton MakeSecBtn(string text, int x, int y)
        {
            RButton b = new RButton();
            b.Text = text;
            b.Font = new Font("Segoe UI", 9.5f);
            b.Location = new Point(x, y);
            b.Size = new Size(136, 38);
            return b;
        }

        Check MakeCheck(string text, int x, int y, int w, bool isChecked)
        {
            Check c = new Check();
            c.Text = text;
            c.Location = new Point(x, y);
            c.Size = new Size(w, 26);
            c.Font = new Font("Segoe UI", 10f);
            c.Checked = isChecked;
            return c;
        }

        // ---------------------------------------------------------- caminhos e configurações
        void SetupPaths()
        {
            string dir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            try
            {
                string test = Path.Combine(dir, ".teste_escrita");
                File.WriteAllText(test, "x");
                File.Delete(test);
            }
            catch (Exception)
            {
                dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Espelho");
                Directory.CreateDirectory(dir);
            }
            baseDir = dir;
            progDir = Path.Combine(dir, "programa");
            scrcpyExe = Path.Combine(progDir, "scrcpy.exe");
            adbExe = Path.Combine(progDir, "adb.exe");
            cfgFile = Path.Combine(dir, "configuracoes.ini");
        }

        void LoadConfig()
        {
            try
            {
                if (!File.Exists(cfgFile)) return;
                foreach (string line in File.ReadAllLines(cfgFile, Encoding.UTF8))
                {
                    int i = line.IndexOf('=');
                    if (i <= 0) continue;
                    cfg[line.Substring(0, i).Trim()] = line.Substring(i + 1).Trim();
                }
            }
            catch (Exception) { }
        }

        string CfgGet(string key, string def)
        {
            string v;
            if (cfg.TryGetValue(key, out v)) return v;
            return def;
        }
        bool CfgBool(string key, bool def) { return CfgGet(key, def ? "1" : "0") == "1"; }
        int CfgInt(string key, int def)
        {
            int n;
            if (int.TryParse(CfgGet(key, def.ToString()), out n)) return n;
            return def;
        }

        void SaveSettings()
        {
            cfg["quality"] = qualityCombo.SelectedIndex.ToString();
            cfg["fullscreen"] = chkFull.Checked ? "1" : "0";
            cfg["screenoff"] = chkOff.Checked ? "1" : "0";
            cfg["pad"] = chkPad.Checked ? "1" : "0";
            cfg["audio"] = chkAudio.Checked ? "1" : "0";
            cfg["touch"] = chkTouch.Checked ? "1" : "0";
            cfg["showtouches"] = chkShow.Checked ? "1" : "0";
            if (appsLoaded && appCombo.SelectedIndex >= 0 && appCombo.SelectedIndex < appPkgs.Count)
            {
                cfg["app"] = appPkgs[appCombo.SelectedIndex] ?? "";
            }
            try
            {
                List<string> lines = new List<string>();
                foreach (KeyValuePair<string, string> kv in cfg) lines.Add(kv.Key + "=" + kv.Value);
                File.WriteAllLines(cfgFile, lines.ToArray(), Encoding.UTF8);
            }
            catch (Exception) { }
        }

        // ---------------------------------------------------------- utilidades de interface
        void UI(Action a)
        {
            try
            {
                if (!IsDisposed && IsHandleCreated) BeginInvoke(a);
            }
            catch (Exception) { }
        }

        void Info(string text, MessageBoxIcon icon)
        {
            MessageBox.Show(this, text, "Espelhô", MessageBoxButtons.OK, icon);
        }

        void SetState(UiState s, string title, string desc, string hex)
        {
            string k = s.ToString() + "|" + title + "|" + desc;
            if (k == stateKey) return;
            stateKey = k;
            uiState = s;
            Color c = ColorTranslator.FromHtml(hex);
            titleLabel.Text = title;
            descLabel.Text = desc;
            statusIcon.State = s;
            statusIcon.Col = c;
            statusIcon.Invalidate();
            UpdateButtons();
        }

        void UpdateButtons()
        {
            // botão principal
            switch (uiState)
            {
                case UiState.Ready:
                    btnPlay.Text = "▶   JOGAR";
                    btnPlay.Style(Theme.Green, ColorTranslator.FromHtml("#34D874"), ColorTranslator.FromHtml("#16A34A"), ColorTranslator.FromHtml("#08210F"));
                    btnPlay.Cursor = Cursors.Hand;
                    break;
                case UiState.Play:
                    btnPlay.Text = "Jogando…";
                    btnPlay.Style(Theme.Accent, Theme.Accent, Theme.Accent, Color.White);
                    btnPlay.Cursor = Cursors.Default;
                    break;
                case UiState.Error:
                    btnPlay.Text = "Tentar de novo";
                    btnPlay.Style(Theme.Accent, ColorTranslator.FromHtml("#8F74FF"), ColorTranslator.FromHtml("#6A49F0"), Color.White);
                    btnPlay.Cursor = Cursors.Hand;
                    break;
                default:
                    btnPlay.Text = "Aguardando o celular…";
                    Color gray = ColorTranslator.FromHtml("#2B3048");
                    btnPlay.Style(gray, gray, gray, Theme.Muted);
                    btnPlay.Cursor = Cursors.Default;
                    break;
            }
            // gravar
            if (rec)
            {
                btnRec.Text = (uiState == UiState.Play) ? "■  Parar gravação" : "●  Gravar: ligado";
                btnRec.Style(ColorTranslator.FromHtml("#DC2626"), ColorTranslator.FromHtml("#EF4444"), ColorTranslator.FromHtml("#B91C1C"), Color.White);
            }
            else
            {
                btnRec.Text = "●  Gravar";
                btnRec.Style(Theme.Card, Theme.Field, Theme.Line, Theme.Text);
            }
            // demais
            bool ready = (uiState == UiState.Ready);
            btnWifi.Enabled = ready && !wireless;
            btnRefApps.Enabled = ready && !appsLoading;
            btnShot.Enabled = ready || uiState == UiState.Play;
        }

        // ---------------------------------------------------------- preparação (download do scrcpy)
        void Prepare()
        {
            busy = true;
            Thread t = new Thread(PrepareWorker);
            t.IsBackground = true;
            t.Start();
        }

        void PrepareWorker()
        {
            bool ok = File.Exists(scrcpyExe);
            if (!ok)
            {
                UI(delegate
                {
                    bar.Visible = true;
                    bar.Value = 0;
                    SetState(UiState.Download, "Preparando tudo", "Baixando o necessário. Isso só acontece na primeira vez e precisa de internet.", "#7C5CFF");
                });
                ok = DownloadProgram();
            }
            string help = "";
            if (ok)
            {
                Proc.StartAdbServer(adbExe);
                help = Proc.Run(scrcpyExe, "--help", 8000, progDir);
            }
            bool done = ok;
            UI(delegate
            {
                busy = false;
                bar.Visible = false;
                bar.Value = -1;
                if (done)
                {
                    ApplyFeatures(help);
                    stateKey = "";
                    timer.Start();
                    PollTick();
                }
                else
                {
                    SetState(UiState.Error, "Não consegui baixar", "Verifique a internet e clique em Tentar de novo.", "#EF4444");
                }
            });
        }

        bool DownloadProgram()
        {
            try
            {
                string url = null;
                try
                {
                    using (WebClient wc = new WebClient())
                    {
                        wc.Headers[HttpRequestHeader.UserAgent] = "Espelho";
                        string json = wc.DownloadString("https://api.github.com/repos/Genymobile/scrcpy/releases/latest");
                        Match m = Regex.Match(json, "\"browser_download_url\"\\s*:\\s*\"([^\"]*scrcpy-win64-[^\"]*\\.zip)\"");
                        if (m.Success) url = m.Groups[1].Value;
                    }
                }
                catch (Exception) { }
                if (url == null) url = "https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-win64-v3.1.zip";

                string zip = Path.Combine(baseDir, "baixando.zip");
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
                req.UserAgent = "Espelho";
                req.Timeout = 30000;
                req.ReadWriteTimeout = 30000;
                using (WebResponse resp = req.GetResponse())
                using (Stream input = resp.GetResponseStream())
                using (FileStream fs = File.Create(zip))
                {
                    long total = resp.ContentLength;
                    long done = 0;
                    byte[] buf = new byte[65536];
                    int n;
                    int last = -1;
                    while ((n = input.Read(buf, 0, buf.Length)) > 0)
                    {
                        fs.Write(buf, 0, n);
                        done += n;
                        if (total > 0)
                        {
                            int pct = (int)(done * 100 / total);
                            if (pct != last)
                            {
                                last = pct;
                                double frac = (double)done / total;
                                string msg = "Baixando… " + pct + "%\nSó acontece na primeira vez.";
                                UI(delegate { bar.Value = frac; descLabel.Text = msg; });
                            }
                        }
                    }
                }
                UI(delegate { descLabel.Text = "Instalando… quase lá."; });
                string tmp = Path.Combine(baseDir, "temp_extraido");
                if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
                ZipFile.ExtractToDirectory(zip, tmp);
                string[] dirs = Directory.GetDirectories(tmp);
                if (dirs.Length == 0) return false;
                if (Directory.Exists(progDir)) Directory.Delete(progDir, true);
                Directory.Move(dirs[0], progDir);
                Directory.Delete(tmp, true);
                File.Delete(zip);
                return File.Exists(scrcpyExe);
            }
            catch (Exception)
            {
                return false;
            }
        }

        void ApplyFeatures(string help)
        {
            featHover = help.Contains("no-mouse-hover");
            featStartApp = help.Contains("start-app");
            featGamepad = help.Contains("--gamepad");
            chkPad.Enabled = featGamepad;
            chkTouch.Enabled = featHover;
            if (!featGamepad)
            {
                tip.SetToolTip(chkPad, "Esta versão do programa de espelhamento não aceita controle. Apague a pasta \"programa\" para baixar a versão mais nova.");
            }
        }

        // ---------------------------------------------------------- celular conectado
        void PollTick()
        {
            if (busy || game != null || polling) return;
            polling = true;
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                string raw = Proc.Run(adbExe, "devices", 6000, null);
                UI(delegate { polling = false; ApplyDevices(raw); });
            });
        }

        void ApplyDevices(string raw)
        {
            if (game != null) return;
            string readySerial = null;
            bool anyUnauth = false;
            foreach (string line in raw.Split('\n'))
            {
                Match m = Regex.Match(line.TrimEnd('\r'), @"^(\S+)\s+(device|unauthorized|offline)\b");
                if (!m.Success) continue;
                string st = m.Groups[2].Value;
                if (st == "device") { if (readySerial == null) readySerial = m.Groups[1].Value; }
                else if (st == "unauthorized") anyUnauth = true;
            }
            if (readySerial != null)
            {
                bool changed = (serial != readySerial);
                serial = readySerial;
                wireless = serial.Contains(":");
                if (changed)
                {
                    phoneName = null;
                    FetchPhoneName(serial);
                }
                ShowReady();
                if (changed || appsFor != serial) BeginApps();
            }
            else if (anyUnauth)
            {
                serial = null;
                wireless = false;
                SetState(UiState.Allow, "Falta uma permissão", "Olhe a tela do celular e toque em Permitir (marque Sempre permitir neste computador).", "#F59E0B");
            }
            else
            {
                serial = null;
                wireless = false;
                SetState(UiState.NoDevice, "Conecte o celular", "Ligue o celular ao PC com o cabo USB e desbloqueie a tela.\nPrimeira vez? Clique em Ajuda.", "#7C5CFF");
            }
            UpdateButtons();
        }

        void ShowReady()
        {
            string n = phoneName ?? "Seu celular";
            SetState(UiState.Ready, "Celular conectado",
                n + " está pronto.\nEscolha o jogo e clique em JOGAR. Mantenha o celular desbloqueado.", "#22C55E");
        }

        void FetchPhoneName(string ser)
        {
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                string model = Proc.LastLine(Proc.Run(adbExe, "-s " + ser + " shell getprop ro.product.model", 6000, null));
                string maker = Proc.LastLine(Proc.Run(adbExe, "-s " + ser + " shell getprop ro.product.manufacturer", 6000, null));
                string name = "Seu celular";
                if (model.Length > 0)
                {
                    name = model;
                    if (maker.Length > 0 && !model.StartsWith(maker, StringComparison.OrdinalIgnoreCase))
                    {
                        name = CultureInfo.CurrentCulture.TextInfo.ToTitleCase(maker.ToLower()) + " " + model;
                    }
                }
                UI(delegate
                {
                    if (serial == ser)
                    {
                        phoneName = name;
                        if (uiState == UiState.Ready) ShowReady();
                    }
                });
            });
        }

        // ---------------------------------------------------------- lista de jogos
        void BeginApps()
        {
            if (serial == null || appsLoading || !File.Exists(scrcpyExe)) return;
            appsLoading = true;
            appsFor = serial;
            string ser = serial;
            appCombo.Items.Clear();
            appCombo.Items.Add("Carregando seus apps…");
            appCombo.SelectedIndex = 0;
            UpdateButtons();
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                string raw = Proc.Run(scrcpyExe, "-s " + ser + " --list-apps", 25000, progDir);
                UI(delegate { appsLoading = false; ApplyApps(raw); });
            });
        }

        void ApplyApps(string raw)
        {
            List<AppItem> user = new List<AppItem>();
            List<AppItem> all = new List<AppItem>();
            Regex pkgRx = new Regex(@"^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$");
            foreach (string line in raw.Split('\n'))
            {
                Match m = Regex.Match(line.TrimEnd('\r'), @"^\s*(?:\[server\]\s+\w+:\s*)?([*-])\s+(\S.*)$");
                if (!m.Success) continue;
                string flag = m.Groups[1].Value;
                string rest = m.Groups[2].Value.Trim();
                string[] tok = Regex.Split(rest, @"\s+");
                string pkg = null;
                string label = "";
                if (pkgRx.IsMatch(tok[tok.Length - 1]))
                {
                    pkg = tok[tok.Length - 1];
                    label = string.Join(" ", tok, 0, tok.Length - 1);
                }
                else if (pkgRx.IsMatch(tok[0]))
                {
                    pkg = tok[0];
                    label = string.Join(" ", tok, 1, tok.Length - 1);
                }
                if (pkg == null) continue;
                if (label.Trim().Length == 0) label = pkg;
                AppItem item = new AppItem();
                item.Label = label.Trim();
                item.Pkg = pkg;
                all.Add(item);
                if (flag == "-") user.Add(item);
            }
            List<AppItem> list = (user.Count > 0) ? user : all;
            list.Sort(delegate(AppItem a, AppItem b)
            {
                return string.Compare(a.Label, b.Label, StringComparison.CurrentCultureIgnoreCase);
            });
            appCombo.Items.Clear();
            appPkgs = new List<string>();
            appCombo.Items.Add(NoApp);
            appPkgs.Add(null);
            foreach (AppItem it in list)
            {
                appCombo.Items.Add(it.Label);
                appPkgs.Add(it.Pkg);
            }
            int idx = 0;
            string saved = CfgGet("app", "");
            if (saved.Length > 0)
            {
                for (int i = 1; i < appPkgs.Count; i++)
                {
                    if (appPkgs[i] == saved) { idx = i; break; }
                }
            }
            appCombo.SelectedIndex = idx;
            appsLoaded = (list.Count > 0);
            UpdateButtons();
        }

        // ---------------------------------------------------------- jogar
        void OnPlayClick()
        {
            if (uiState == UiState.Error) Prepare();
            else if (uiState == UiState.Ready) StartGame();
        }

        string GamesDir()
        {
            string desk = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
            if (string.IsNullOrEmpty(desk)) desk = baseDir;
            string d = Path.Combine(desk, "Jogos");
            if (!Directory.Exists(d)) Directory.CreateDirectory(d);
            return d;
        }

        void OpenGamesFolder()
        {
            try { Process.Start("explorer.exe", "\"" + GamesDir() + "\""); }
            catch (Exception) { Info("Não consegui abrir a pasta Jogos.", MessageBoxIcon.Warning); }
        }

        void StartGame()
        {
            if (uiState != UiState.Ready || serial == null) return;
            SaveSettings();
            StringBuilder a = new StringBuilder();
            a.Append("-s ").Append(serial);
            a.Append(" --window-title=\"Espelho\" --max-fps=60 --stay-awake ");
            a.Append(QualityArgs[qualityCombo.SelectedIndex]);
            if (chkFull.Checked) a.Append(" -f");
            if (!chkAudio.Checked) a.Append(" --no-audio");
            if (chkOff.Checked) a.Append(" -S");
            if (chkTouch.Checked && featHover) a.Append(" --no-mouse-hover");
            if (chkPad.Checked && featGamepad) a.Append(" --gamepad=uhid");
            if (chkShow.Checked) a.Append(" --show-touches");
            if (featStartApp && appsLoaded && appCombo.SelectedIndex > 0 && appCombo.SelectedIndex < appPkgs.Count)
            {
                string pkg = appPkgs[appCombo.SelectedIndex];
                if (pkg != null && Regex.IsMatch(pkg, @"^[A-Za-z0-9_.]+$")) a.Append(" --start-app=").Append(pkg);
            }
            recFile = null;
            if (rec)
            {
                try
                {
                    recFile = Path.Combine(GamesDir(), "Partida_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss") + ".mp4");
                    a.Append(" --record=\"").Append(recFile).Append("\"");
                }
                catch (Exception) { recFile = null; }
            }
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(scrcpyExe, a.ToString());
                psi.WorkingDirectory = progDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                Process p = new Process();
                p.StartInfo = psi;
                p.EnableRaisingEvents = true;
                StringBuilder log = new StringBuilder();
                DataReceivedEventHandler h = delegate(object sender, DataReceivedEventArgs ev)
                {
                    if (ev.Data != null) { lock (log) { log.AppendLine(ev.Data); } }
                };
                p.OutputDataReceived += h;
                p.ErrorDataReceived += h;
                p.Exited += delegate(object sender, EventArgs ev) { UI(delegate { OnGameExited(p); }); };
                p.Start();
                p.BeginOutputReadLine();
                p.BeginErrorReadLine();
                game = p;
                gameLog = log;
                string desc = "O jogo está aberto em outra janela.\nPara parar, é só fechar a janela do jogo.";
                if (recFile != null) desc = "Gravando a partida na pasta Jogos.\nPara parar, feche a janela do jogo.";
                SetState(UiState.Play, "Jogando!", desc, "#7C5CFF");
            }
            catch (Exception ex)
            {
                recFile = null;
                Info("Não consegui abrir o jogo.\n" + ex.Message, MessageBoxIcon.Error);
            }
        }

        void OnGameExited(Process p)
        {
            if (p != game) return;
            int code = 0;
            try { code = p.ExitCode; } catch (Exception) { }
            string log = "";
            if (gameLog != null) { lock (gameLog) { log = gameLog.ToString(); } }
            game = null;
            gameLog = null;
            stateKey = "";
            if (serial != null) ShowReady(); else SetState(UiState.NoDevice, "Conecte o celular", "Ligue o celular ao PC com o cabo USB e desbloqueie a tela.\nPrimeira vez? Clique em Ajuda.", "#7C5CFF");
            PollTick();
            if (code != 0)
            {
                List<string> lines = new List<string>();
                foreach (string l in log.Split('\n'))
                {
                    if (l.Trim().Length > 0) lines.Add(l.Trim());
                }
                int start = Math.Max(0, lines.Count - 5);
                string tail = string.Join("\n", lines.GetRange(start, lines.Count - start).ToArray());
                Info("O jogo foi fechado de forma inesperada.\nConfira se o cabo está bem conectado e se o celular está desbloqueado.\n\n" + tail, MessageBoxIcon.Warning);
            }
            FinishRecord();
        }

        void RestartGame()
        {
            Process old = game;
            if (old == null) return;
            game = null;
            Cursor = Cursors.WaitCursor;
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                try
                {
                    old.CloseMainWindow();
                    if (!old.WaitForExit(6000))
                    {
                        old.Kill();
                        old.WaitForExit(2000);
                    }
                }
                catch (Exception) { }
                UI(delegate
                {
                    Cursor = Cursors.Default;
                    FinishRecord();
                    stateKey = "";
                    ShowReady();
                    StartGame();
                });
            });
        }

        void ToggleRec()
        {
            rec = !rec;
            UpdateButtons();
            if (game != null) RestartGame();
        }

        void FinishRecord()
        {
            string f = recFile;
            recFile = null;
            if (f != null && File.Exists(f) && new FileInfo(f).Length > 1000)
            {
                DialogResult r = MessageBox.Show(this,
                    "Gravação salva na pasta Jogos:\n" + Path.GetFileName(f) + "\n\nQuer abrir a pasta?",
                    "Espelhô", MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r == DialogResult.Yes) OpenGamesFolder();
            }
        }

        // ---------------------------------------------------------- captura de tela
        void TakeShot()
        {
            if (serial == null) { Info("Conecte o celular primeiro.", MessageBoxIcon.Warning); return; }
            string ser = serial;
            string file;
            try
            {
                file = Path.Combine(GamesDir(), "Print_" + DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss") + ".png");
            }
            catch (Exception)
            {
                Info("Não consegui criar a pasta Jogos.", MessageBoxIcon.Warning);
                return;
            }
            Cursor = Cursors.WaitCursor;
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                bool ok = Proc.RunToFile(adbExe, "-s " + ser + " exec-out screencap -p", file, 12000);
                if (ok)
                {
                    try { ok = new FileInfo(file).Length > 2000; } catch (Exception) { ok = false; }
                }
                if (!ok)
                {
                    try { if (File.Exists(file)) File.Delete(file); } catch (Exception) { }
                }
                bool result = ok;
                UI(delegate
                {
                    Cursor = Cursors.Default;
                    if (result)
                    {
                        btnShot.Text = "Salvo ✓";
                        flashTimer.Stop();
                        flashTimer.Start();
                    }
                    else
                    {
                        Info("Não consegui tirar a foto da tela.\nAlguns apps bloqueiam capturas. Tente de novo.", MessageBoxIcon.Warning);
                    }
                });
            });
        }

        // ---------------------------------------------------------- Wi-Fi
        void ConnectWifi()
        {
            if (uiState != UiState.Ready || serial == null || wireless) return;
            string ser = serial;
            Cursor = Cursors.WaitCursor;
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                string ip = null;
                string route = Proc.Run(adbExe, "-s " + ser + " shell ip route", 6000, null);
                Match m = Regex.Match(route, @"dev wlan0.*?src (\d+\.\d+\.\d+\.\d+)");
                if (m.Success) ip = m.Groups[1].Value;
                if (ip == null)
                {
                    UI(delegate
                    {
                        Cursor = Cursors.Default;
                        Info("Não achei o Wi-Fi do celular.\nLigue o Wi-Fi no celular, use a mesma rede do computador e tente de novo.", MessageBoxIcon.Warning);
                    });
                    return;
                }
                Proc.Run(adbExe, "-s " + ser + " tcpip 5555", 6000, null);
                Thread.Sleep(2000);
                string r = Proc.Run(adbExe, "connect " + ip + ":5555", 8000, null);
                bool ok = r.Contains("connected to");
                UI(delegate
                {
                    Cursor = Cursors.Default;
                    if (ok)
                    {
                        Info("Pronto! O celular está conectado por Wi-Fi.\nAgora você já pode tirar o cabo USB.\n\n(A imagem pode ter um pouco mais de atraso que no cabo.)", MessageBoxIcon.Information);
                        PollTick();
                    }
                    else
                    {
                        Info("Não deu certo conectar por Wi-Fi.\nConfira se o celular e o PC estão na mesma rede e tente de novo, ou continue usando o cabo.", MessageBoxIcon.Warning);
                    }
                });
            });
        }

        // ---------------------------------------------------------- atalho na Área de Trabalho
        void CreateShortcut()
        {
            try
            {
                string desk = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string lnk = Path.Combine(desk, "Espelhô.lnk");
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                object shell = Activator.CreateInstance(shellType);
                object link = shellType.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
                Type lt = link.GetType();
                lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { Application.ExecutablePath });
                lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { baseDir });
                lt.InvokeMember("IconLocation", BindingFlags.SetProperty, null, link, new object[] { Application.ExecutablePath + ",0" });
                lt.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { "Espelhô - seu celular na tela do PC" });
                lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
                Info("Atalho criado na Área de Trabalho:\n\"Espelhô\"\n\nSe você mudar o Espelho.exe de pasta, crie o atalho de novo.", MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Info("Não consegui criar o atalho.\n" + ex.Message, MessageBoxIcon.Warning);
            }
        }

        // ---------------------------------------------------------- fechar
        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            SaveSettings();
            if (timer != null) timer.Stop();
            if (rec && game != null)
            {
                try { game.CloseMainWindow(); game.WaitForExit(5000); } catch (Exception) { }
            }
            base.OnFormClosing(e);
        }
    }
}
