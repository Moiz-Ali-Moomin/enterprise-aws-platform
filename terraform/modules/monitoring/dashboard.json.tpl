{
    "widgets": [
        {
            "type": "metric",
            "x": 0,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ECS", "CPUUtilization", "ServiceName", "${ecs_service_name}", "ClusterName", "${ecs_cluster_name}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${region}",
                "title": "${project_name} - ${environment} - CPU Utilization"
            }
        },
        {
            "type": "metric",
            "x": 12,
            "y": 0,
            "width": 12,
            "height": 6,
            "properties": {
                "metrics": [
                    [ "AWS/ECS", "MemoryUtilization", "ServiceName", "${ecs_service_name}", "ClusterName", "${ecs_cluster_name}" ]
                ],
                "period": 300,
                "stat": "Average",
                "region": "${region}",
                "title": "${project_name} - ${environment} - Memory Utilization"
            }
        }
    ]
}
