FROM grafana/alloy:v1.20.0
COPY config.alloy /etc/alloy/config.alloy
COPY start.sh /etc/alloy/start.sh
EXPOSE 4318
ENTRYPOINT ["/bin/sh", "/etc/alloy/start.sh"]
