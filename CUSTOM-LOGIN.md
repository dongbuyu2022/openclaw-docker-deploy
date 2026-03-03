# 自定义登录页面

## 功能特性

✨ **美观的登录界面**
- 渐变背景 + 动态粒子效果
- 毛玻璃效果卡片
- 流畅的动画过渡

🌍 **中英文切换**
- 支持中文/English 切换
- 自动记住语言偏好
- 所有文本完全本地化

🎨 **自定义系统名称**
- 在部署时设置系统名称
- 登录页面显示自定义名称
- 支持中英文名称

📱 **响应式设计**
- 完美适配桌面和移动端
- 触摸友好的交互

## 使用方法

### 方法一：部署时自动配置

运行交互式部署脚本时，会提示你输入系统名称：

```bash
./setup-interactive.sh
```

脚本会询问：
1. 使用默认名称（OpenClaw AI）
2. 自定义名称

### 方法二：手动生成

```bash
# 生成自定义登录页面
./generate-login-page.sh "我的AI助手"

# 或使用英文名称
./generate-login-page.sh "My AI Assistant"
```

### 方法三：部署后修改

如果已经部署完成，想修改系统名称：

```bash
# 1. 生成新的登录页面
./generate-login-page.sh "新的系统名称"

# 2. 重启 Nginx 服务
docker compose restart nginx
```

## 预览效果

### 中文界面
- 系统名称：你设置的名称
- 副标题：AI 智能助手平台
- 用户名/密码输入框
- 记住我选项
- 登录按钮

### English Interface
- System Name: Your custom name
- Subtitle: AI Assistant Platform
- Username/Password fields
- Remember me option
- Sign In button

## 技术特性

### 动画效果
- 页面加载淡入动画
- Logo 脉冲动画
- 背景粒子浮动动画
- 按钮悬停效果

### 安全特性
- 密码输入框自动隐藏
- 支持"记住我"功能
- HTTPS 加密传输

### 浏览器兼容
- Chrome/Edge (最新版)
- Firefox (最新版)
- Safari (最新版)
- 移动端浏览器

## 自定义样式

如果你想进一步自定义样式，可以编辑生成的 HTML 文件：

```bash
nano authelia/custom-login.html
```

可以修改的内容：
- 背景渐变颜色
- Logo 图标（默认 🤖）
- 字体和字号
- 动画速度
- 按钮样式

修改后重启 Nginx：
```bash
docker compose restart nginx
```

## 常见问题

### Q: 如何更改 Logo 图标？

A: 编辑 `authelia/custom-login.html`，找到：
```html
<div class="logo">🤖</div>
```
将 🤖 替换为你喜欢的 emoji 或文字。

### Q: 如何更改背景颜色？

A: 编辑 CSS 中的 `background` 属性：
```css
background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
```

### Q: 语言切换不生效？

A: 清除浏览器缓存或使用无痕模式访问。

### Q: 如何禁用动画效果？

A: 编辑 HTML，删除或注释掉 `createParticles()` 函数调用。

## 文件位置

- 生成脚本：`./generate-login-page.sh`
- 生成的页面：`authelia/custom-login.html`
- 模板文件：`authelia/login-template.html`

## 注意事项

1. 系统名称建议 2-20 个字符
2. 支持中英文、数字、符号
3. 修改后需要重启 Nginx 才能生效
4. 建议使用有意义的名称，方便识别

## 示例名称

中文示例：
- 我的AI助手
- 智能办公助手
- 小明的AI
- 企业智能平台

English Examples:
- My AI Assistant
- Smart Office Helper
- AI Workspace
- Enterprise AI Platform
