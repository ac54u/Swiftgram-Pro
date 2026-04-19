from telethon import TelegramClient, events
import os
import subprocess
import re

# --- 配置区 ---
api_id = 31394149
api_hash = '27a9d8aba4e3697e5cba6e7e2e285661'
SPLIT_SCRIPT = "/opt/Swiftgram-Pro/tg_split.sh"
DOWNLOAD_PATH = "/root/transfer"

# 确保下载目录存在
os.makedirs(DOWNLOAD_PATH, exist_ok=True)

client = TelegramClient('shugram_session', api_id, api_hash)

print("⚡️ 云端搬运工已上线，正在等待指令...")

@client.on(events.NewMessage(pattern=r'https://t.me/c/(\d+)/(\d+)'))
@client.on(events.NewMessage(pattern=r'https://t.me/(\w+)/(\d+)'))
async def handler(event):
    # 只响应你自己发给自己的指令（收藏夹）
    if not event.is_private or event.chat_id != (await client.get_me()).id:
        return

    url = event.message.message
    print(f"🔍 检测到任务链接: {url}")
    
    # 提取频道和消息 ID
    match = re.search(r't.me/(?:c/)?([^/]+)/(\d+)', url)
    if not match: return
    
    channel = match.group(1)
    msg_id = int(match.group(2))
    
    if channel.isdigit():
        channel = int(f"-100{channel}")

    status_msg = await event.respond("📡 正在尝试抓取大文件...")

    try:
        msg = await client.get_messages(channel, ids=msg_id)
        if not msg or not msg.media:
            await status_msg.edit("❌ 错误: 该消息不包含媒体文件")
            return

        await status_msg.edit(f"📥 正在从 Telegram 服务器满速拉取 (130MB/s 级别)...")
        path = await client.download_media(msg, DOWNLOAD_PATH)
        
        await status_msg.edit("🔪 文件已落地，正在检测体积并尝试切片...")
        subprocess.run([SPLIT_SCRIPT, path], check=True)
        
        base_name = os.path.splitext(path)[0]
        ext = "MOV"
        # 严格匹配 _part_ 结尾的文件
        parts = [f for f in os.listdir(DOWNLOAD_PATH) if f.startswith(os.path.basename(base_name)) and f.endswith(ext) and "_part_" in f]
        parts.sort()

        # 🚀 [新增逻辑] 判断是否真的切片了
        if len(parts) > 0:
            await status_msg.edit(f"🚀 切片完成，正在将 {len(parts)} 个分片发回收藏夹...")
            for p in parts:
                file_path = os.path.join(DOWNLOAD_PATH, p)
                await client.send_file('me', file_path, caption=f"✅ {p} (原画分片)")
                os.remove(file_path) # 烧毁分片
        else:
            # 没切片说明文件小于 1.8GB，直接发原文件
            await status_msg.edit(f"✅ 文件体积安全 (<1.8GB)，无需切片，正在原样发回...")
            await client.send_file('me', path, caption="✅ 完整搬运 (原画)")

        # 烧毁原文件
        if os.path.exists(path):
            os.remove(path)
            
        await status_msg.edit("✨ 全流程处理完毕！视频已安全存储在您的收藏夹。")

    except Exception as e:
        await status_msg.edit(f"⚠️ 任务失败: {str(e)}")

with client:
    client.run_until_disconnected()