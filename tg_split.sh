#!/bin/bash

# 检查是否传入了文件
if [ -z "$1" ]; then
    echo "❌ 错误: 请指定要切片的视频文件!"
    echo "💡 用法: ./tg_split.sh movie.mp4"
    exit 1
fi

INPUT_FILE="$1"
FILENAME="${INPUT_FILE%.*}"
EXTENSION="${INPUT_FILE##*.}"

# 1. 使用 ffprobe 获取视频总时长 (秒)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE")
DURATION=${DURATION%.*} # 取整

# 2. 获取文件总大小 (Bytes) 
FILESIZE=$(wc -c <"$INPUT_FILE")

# 3. 计算目标切片时间 
# Telegram 限制 2GB，我们按 1.8GB (1932735283 Bytes) 为安全阈值切分
TARGET_SIZE=$((1024 * 1024 * 1800))

# 如果文件本身小于 1.8GB，直接退出
if [ "$FILESIZE" -le "$TARGET_SIZE" ]; then
    echo "✅ 文件体积安全 ($((FILESIZE / 1024 / 1024)) MB)，无需切片，直接去 Telegram 上传吧！"
    exit 0
fi

# 计算切片比例和时间段
RATIO=$(echo "scale=4; $TARGET_SIZE / $FILESIZE" | bc)
SEGMENT_TIME=$(echo "scale=0; $DURATION * $RATIO / 1" | bc)

echo "📊 视频总长: ${DURATION}s, 总大小: $((FILESIZE / 1024 / 1024))MB"
echo "🔪 计划按每段 ${SEGMENT_TIME} 秒进行安全切片..."

# 4. 执行无损切片
ffmpeg -i "$INPUT_FILE" \
    -c copy \
    -map 0 \
    -f segment \
    -segment_time "$SEGMENT_TIME" \
    -reset_timestamps 1 \
    "${FILENAME}_part_%03d.${EXTENSION}"

echo "🎉 切片完成！你的文件现在可以安全上传到 Telegram 了。"
