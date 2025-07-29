#!/bin/bash


echo `date +%Y%m%d%H%M%S` " - docker ps"
clear_thought_running=$(docker ps --filter "ancestor=waldzellai/clear-thought" | grep "waldzellai/clear-thought" | wc -l)
if [[ "$clear_thought_running" -eq 1 ]]; then
    echo `date +%Y%m%d%H%M%S` " - echo already running"
    echo "Docker container for Clear Thought MCP already running"
else
    echo `date +%Y%m%d%H%M%S` " - script disabled=true"
    .kiro/settings/modifyMcpJson.sh true
    echo `date +%Y%m%d%H%M%S` " - sleep 1s"
    sleep 1s
    echo `date +%Y%m%d%H%M%S` " - docker"
    docker run --rm -d -p 3000:3000 waldzellai/clear-thought
    echo `date +%Y%m%d%H%M%S` " - sleep 4s"
    sleep 4s
fi

echo `date +%Y%m%d%H%M%S` " - script disabled=false"
.kiro/settings/modifyMcpJson.sh false