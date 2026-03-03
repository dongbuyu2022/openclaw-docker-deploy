#!/bin/bash

# 生成自定义登录页面
# 参数: $1 = 系统名称

SYSTEM_NAME="${1:-OpenClaw AI}"
OUTPUT_FILE="authelia/custom-login.html"

mkdir -p authelia

cat > "$OUTPUT_FILE" << 'EOF'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SYSTEM_NAME_PLACEHOLDER - 登录</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            overflow: hidden;
            position: relative;
        }

        .particles {
            position: absolute;
            width: 100%;
            height: 100%;
            overflow: hidden;
            z-index: 0;
        }

        .particle {
            position: absolute;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 50%;
            animation: float 15s infinite;
        }

        @keyframes float {
            0%, 100% { transform: translateY(0) translateX(0) scale(1); opacity: 0; }
            10% { opacity: 0.3; }
            90% { opacity: 0.3; }
            100% { transform: translateY(-100vh) translateX(50px) scale(1.5); opacity: 0; }
        }

        .login-container {
            position: relative;
            z-index: 1;
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            padding: 50px 40px;
            width: 90%;
            max-width: 420px;
            animation: slideIn 0.6s ease-out;
        }

        @keyframes slideIn {
            from { opacity: 0; transform: translateY(30px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .logo-section { text-align: center; margin-bottom: 40px; }

        .logo {
            width: 80px;
            height: 80px;
            margin: 0 auto 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 20px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 40px;
            color: white;
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.4);
            animation: pulse 2s ease-in-out infinite;
        }

        @keyframes pulse {
            0%, 100% { transform: scale(1); }
            50% { transform: scale(1.05); }
        }

        .system-name {
            font-size: 28px;
            font-weight: 700;
            color: #2d3748;
            margin-bottom: 8px;
        }

        .system-subtitle {
            font-size: 14px;
            color: #718096;
        }

        .language-switch {
            position: absolute;
            top: 20px;
            right: 20px;
            display: flex;
            gap: 10px;
        }

        .lang-btn {
            padding: 6px 12px;
            border: 2px solid #e2e8f0;
            background: white;
            border-radius: 8px;
            cursor: pointer;
            font-size: 12px;
            color: #718096;
            transition: all 0.3s;
        }

        .lang-btn.active {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-color: transparent;
        }

        .lang-btn:hover { border-color: #667eea; }

        .login-form { margin-top: 30px; }
        .form-group { margin-bottom: 20px; }

        .form-label {
            display: block;
            font-size: 14px;
            font-weight: 600;
            color: #4a5568;
            margin-bottom: 8px;
        }

        .form-input {
            width: 100%;
            padding: 14px 16px;
            border: 2px solid #e2e8f0;
            border-radius: 10px;
            font-size: 15px;
            transition: all 0.3s;
            background: white;
        }

        .form-input:focus {
            outline: none;
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }

        .form-input::placeholder { color: #cbd5e0; }

        .remember-me {
            display: flex;
            align-items: center;
            margin-bottom: 25px;
        }

        .remember-me input[type="checkbox"] {
            width: 18px;
            height: 18px;
            margin-right: 8px;
            cursor: pointer;
        }

        .remember-me label {
            font-size: 14px;
            color: #4a5568;
            cursor: pointer;
        }

        .login-button {
            width: 100%;
            padding: 14px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 10px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
        }

        .login-button:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(102, 126, 234, 0.5);
        }

        .login-button:active { transform: translateY(0); }

        .footer-info {
            margin-top: 30px;
            text-align: center;
            font-size: 12px;
            color: #a0aec0;
        }

        .footer-info a {
            color: #667eea;
            text-decoration: none;
        }

        .footer-info a:hover { text-decoration: underline; }

        @media (max-width: 480px) {
            .login-container { padding: 40px 30px; }
            .system-name { font-size: 24px; }
        }
    </style>
</head>
<body>
    <div class="particles" id="particles"></div>

    <div class="login-container">
        <div class="language-switch">
            <button class="lang-btn active" data-lang="zh">中文</button>
            <button class="lang-btn" data-lang="en">English</button>
        </div>

        <div class="logo-section">
            <div class="logo">🤖</div>
            <h1 class="system-name" data-i18n="systemName">SYSTEM_NAME_PLACEHOLDER</h1>
            <p class="system-subtitle" data-i18n="subtitle">AI 智能助手平台</p>
        </div>

        <form class="login-form" action="/authelia" method="GET">
            <div class="form-group">
                <label class="form-label" for="username" data-i18n="username">用户名</label>
                <input type="text" id="username" name="username" class="form-input"
                       data-i18n-placeholder="usernamePlaceholder" placeholder="请输入用户名" required>
            </div>

            <div class="form-group">
                <label class="form-label" for="password" data-i18n="password">密码</label>
                <input type="password" id="password" name="password" class="form-input"
                       data-i18n-placeholder="passwordPlaceholder" placeholder="请输入密码" required>
            </div>

            <div class="remember-me">
                <input type="checkbox" id="rememberMe" name="rememberMe">
                <label for="rememberMe" data-i18n="rememberMe">记住我</label>
            </div>

            <button type="submit" class="login-button" data-i18n="loginButton">登录</button>
        </form>

        <div class="footer-info">
            <p data-i18n="footer">Powered by <a href="https://openclaw.ai" target="_blank">OpenClaw</a></p>
        </div>
    </div>

    <script>
        const i18n = {
            zh: {
                systemName: 'SYSTEM_NAME_PLACEHOLDER',
                subtitle: 'AI 智能助手平台',
                username: '用户名',
                usernamePlaceholder: '请输入用户名',
                password: '密码',
                passwordPlaceholder: '请输入密码',
                rememberMe: '记住我',
                loginButton: '登录',
                footer: 'Powered by <a href="https://openclaw.ai" target="_blank">OpenClaw</a>'
            },
            en: {
                systemName: 'SYSTEM_NAME_PLACEHOLDER',
                subtitle: 'AI Assistant Platform',
                username: 'Username',
                usernamePlaceholder: 'Enter your username',
                password: 'Password',
                passwordPlaceholder: 'Enter your password',
                rememberMe: 'Remember me',
                loginButton: 'Sign In',
                footer: 'Powered by <a href="https://openclaw.ai" target="_blank">OpenClaw</a>'
            }
        };

        let currentLang = localStorage.getItem('language') || 'zh';

        function switchLanguage(lang) {
            currentLang = lang;
            localStorage.setItem('language', lang);
            document.documentElement.lang = lang;

            document.querySelectorAll('[data-i18n]').forEach(el => {
                const key = el.getAttribute('data-i18n');
                if (i18n[lang][key]) el.innerHTML = i18n[lang][key];
            });

            document.querySelectorAll('[data-i18n-placeholder]').forEach(el => {
                const key = el.getAttribute('data-i18n-placeholder');
                if (i18n[lang][key]) el.placeholder = i18n[lang][key];
            });

            document.querySelectorAll('.lang-btn').forEach(btn => {
                btn.classList.toggle('active', btn.getAttribute('data-lang') === lang);
            });
        }

        switchLanguage(currentLang);

        document.querySelectorAll('.lang-btn').forEach(btn => {
            btn.addEventListener('click', () => switchLanguage(btn.getAttribute('data-lang')));
        });

        function createParticles() {
            const container = document.getElementById('particles');
            for (let i = 0; i < 30; i++) {
                const particle = document.createElement('div');
                particle.className = 'particle';
                const size = Math.random() * 60 + 20;
                particle.style.width = size + 'px';
                particle.style.height = size + 'px';
                particle.style.left = Math.random() * 100 + '%';
                particle.style.bottom = '-' + size + 'px';
                particle.style.animationDelay = Math.random() * 15 + 's';
                particle.style.animationDuration = (Math.random() * 10 + 10) + 's';
                container.appendChild(particle);
            }
        }

        createParticles();
    </script>
</body>
</html>
EOF

# 替换系统名称
sed -i "s/SYSTEM_NAME_PLACEHOLDER/$SYSTEM_NAME/g" "$OUTPUT_FILE"

echo "✓ 自定义登录页面已生成：$OUTPUT_FILE"
echo "  系统名称：$SYSTEM_NAME"
