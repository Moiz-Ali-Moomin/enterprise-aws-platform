resource "aws_appmesh_mesh" "main" {
  name = var.mesh_name

  spec {
    egress_filter {
      type = "ALLOW_ALL"
    }
  }
}

resource "aws_appmesh_virtual_node" "service_a" {
  name      = "service-a-vn"
  mesh_name = aws_appmesh_mesh.main.name

  spec {
    listener {
      port_mapping {
        port     = 8000
        protocol = "http"
      }

      tls {
        mode = "STRICT"
        certificate {
          acm {
            certificate_arn = var.certificate_arn
          }
        }
      }
    }

    service_discovery {
      aws_cloud_map {
        service_name   = "service-a"
        namespace_name = var.namespace_name
      }
    }
  }
}
