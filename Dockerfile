FROM grafana/alloy:v1.14.1
COPY config.alloy /etc/alloy/config.alloy
COPY mapping-statsd.yaml /etc/alloy/mapping-statsd.yaml
ENTRYPOINT ["/bin/alloy", "run", "--storage.path=/var/lib/alloy/data"]
