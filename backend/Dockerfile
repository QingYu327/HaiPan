# 飞牛 NAS 的默认镜像加速源对 Docker Hub 返回 401，这里改用 DaoCloud 镜像
FROM docker.m.daocloud.io/library/node:20-alpine

WORKDIR /app
COPY server.js ./

# 数据目录用于持久化用户与名单，挂载宿主机卷
RUN mkdir -p /data && chown -R node:node /data /app
USER node

ENV PORT=8080 DATA_DIR=/data
EXPOSE 8080 8443
VOLUME ["/data"]

CMD ["node", "server.js"]
