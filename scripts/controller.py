#!/usr/bin/env python3
"""
BD SelfScan Kubernetes Controller (Phase 2)

Watches for deployment events and automatically triggers container scans
when applications are deployed or updated.

This controller implements:
1. Kubernetes deployment event watching
2. Application configuration matching
3. Automatic scan job creation
4. Metrics collection and health endpoints
5. Error handling and retry logic
"""

import os
import sys
import json
import time
import yaml
import logging
import asyncio
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any

import kubernetes
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

import prometheus_client
from prometheus_client import Counter, Histogram, Gauge, start_http_server

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger('bd-selfscan-controller')

# Prometheus metrics
DEPLOYMENT_EVENTS = Counter('bd_selfscan_deployment_events_total', 
                           'Total deployment events processed', 
                           ['namespace', 'application', 'event_type'])

SCAN_JOBS_CREATED = Counter('bd_selfscan_jobs_created_total',
                           'Total scan jobs created',
                           ['namespace', 'application'])

SCAN_JOBS_FAILED = Counter('bd_selfscan_jobs_failed_total',
                          'Total scan jobs that failed to create',
                          ['namespace', 'application', 'reason'])

SCAN_DURATION = Histogram('bd_selfscan_job_duration_seconds',
                         'Duration of scan jobs',
                         ['namespace', 'application'],
                         buckets=[60, 300, 600, 1200, 1800, 3600])

POLICY_VIOLATIONS = Counter('bd_selfscan_policy_violations_total',
                           'Total policy violations found',
                           ['namespace', 'application', 'severity'])

CONTROLLER_HEALTH = Gauge('bd_selfscan_controller_healthy',
                         'Controller health status (1=healthy, 0=unhealthy)')

ACTIVE_SCANS = Gauge('bd_selfscan_active_jobs',
                    'Number of currently active scan jobs')

class BDSelfScanController:
    """Main controller class for BD SelfScan automation."""
    
    def __init__(self):
        self.namespace = os.getenv('NAMESPACE', 'bd-selfscan-system')
        self.debug = os.getenv('DEBUG', 'false').lower() == 'true'
        self.applications_config: Dict[str, Dict] = {}
        self.k8s_apps_v1 = None
        self.k8s_batch_v1 = None
        self.k8s_core_v1 = None
        
        # Configure logging level
        if self.debug:
            logging.getLogger().setLevel(logging.DEBUG)
            logger.setLevel(logging.DEBUG)
            
        logger.info(f"Initializing BD SelfScan Controller in namespace: {self.namespace}")
        
        # Initialize Kubernetes client
        self._init_kubernetes()
        
        # Load application configuration
        self._load_applications_config()
        
        # Start metrics server
        self._start_metrics_server()
        
        # Set initial health status
        CONTROLLER_HEALTH.set(1)
    
    def _init_kubernetes(self):
        """Initialize Kubernetes API clients."""
        try:
            # Try to load in-cluster config first
            config.load_incluster_config()
            logger.info("Loaded in-cluster Kubernetes configuration")
        except Exception:
            try:
                # Fallback to local kubeconfig
                config.load_kube_config()
                logger.info("Loaded local Kubernetes configuration")
            except Exception as e:
                logger.error(f"Failed to load Kubernetes configuration: {e}")
                sys.exit(1)
        
        # Initialize API clients
        self.k8s_apps_v1 = client.AppsV1Api()
        self.k8s_batch_v1 = client.BatchV1Api()
        self.k8s_core_v1 = client.CoreV1Api()
        
        logger.info("Kubernetes API clients initialized")
    
    def _start_metrics_server(self):
        """Start Prometheus metrics server."""
        try:
            # Start metrics server on port 8080
            start_http_server(8080)
            logger.info("Prometheus metrics server started on port 8080")
            
            # Start health check server on port 8081
            import http.server
            import socketserver
            from threading import Thread
            
            class HealthHandler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/health':
                        self.send_response(200)
                        self.send_header('Content-type', 'text/plain')
                        self.end_headers()
                        self.wfile.write(b'healthy')
                    elif self.path == '/ready':
                        self.send_response(200)
                        self.send_header('Content-type', 'text/plain')
                        self.end_headers()
                        self.wfile.write(b'ready')
                    else:
                        self.send_response(404)
                        self.end_headers()
                
                def log_message(self, format, *args):
                    pass  # Suppress default logging
            
            health_server = socketserver.TCPServer(("", 8081), HealthHandler)
            health_thread = Thread(target=health_server.serve_forever, daemon=True)
            health_thread.start()
            
            logger.info("Health check server started on port 8081")
        except Exception as e:
            logger.error(f"Failed to start metrics server: {e}")
    
    def _load_applications_config(self):
        """Load application configuration from ConfigMap."""
        try:
            # Read applications ConfigMap
            config_map = self.k8s_core_v1.read_namespaced_config_map(
                name='bd-selfscan-applications',
                namespace=self.namespace
            )
            
            # Parse YAML configuration
            config_data = config_map.data.get('applications.yaml', '')
            if config_data:
                config = yaml.safe_load(config_data)
                applications = config.get('applications', [])
                
                # Index applications by namespace+labelSelector for fast lookup
                self.applications_config = {}
                for app in applications:
                    if app.get('scanOnDeploy', False):  # Only include apps with auto-scan enabled
                        key = f"{app['namespace']}:{app['labelSelector']}"
                        self.applications_config[key] = app
                        logger.debug(f"Loaded application config: {app['name']} -> {key}")
                
                logger.info(f"Loaded {len(self.applications_config)} applications configured for auto-scan")
            else:
                logger.warning("No applications configuration found in ConfigMap")
                
        except ApiException as e:
            logger.error(f"Failed to load applications configuration: {e}")
            CONTROLLER_HEALTH.set(0)
        except Exception as e:
            logger.error(f"Error parsing applications configuration: {e}")
            CONTROLLER_HEALTH.set(0)
    
    def _find_matching_application(self, namespace: str, labels: Dict[str, str]) -> Optional[Dict]:
        """Find matching application configuration for a deployment."""
        for key, app_config in self.applications_config.items():
            config_namespace, label_selector = key.split(':', 1)
            
            if config_namespace != namespace:
                continue
            
            # Parse label selector (simple implementation for common cases)
            required_labels = {}
            for label_pair in label_selector.split(','):
                if '=' in label_pair:
                    k, v = label_pair.strip().split('=', 1)
                    required_labels[k] = v
            
            # Check if all required labels match
            match = True
            for req_key, req_value in required_labels.items():
                if labels.get(req_key) != req_value:
                    match = False
                    break
            
            if match:
                logger.debug(f"Found matching application: {app_config['name']}")
                return app_config
        
        return None
    
    def _create_scan_job(self, app_config: Dict, trigger: str = "deployment") -> bool:
        """Create a scan job for the application."""
        app_name = app_config['name']
        namespace = app_config['namespace']
        
        try:
            # Generate unique job name
            timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
            safe_app_name = app_name.lower().replace(' ', '-').replace('_', '-')
            job_name = f"bd-selfscan-auto-{safe_app_name}-{timestamp}"
            
            # Create job specification
            job_spec = self._build_job_spec(job_name, app_config, trigger)
            
            # Create the job
            self.k8s_batch_v1.create_namespaced_job(
                namespace=self.namespace,
                body=job_spec
            )
            
            logger.info(f"Created scan job '{job_name}' for application '{app_name}'")
            SCAN_JOBS_CREATED.labels(namespace=namespace, application=app_name).inc()
            ACTIVE_SCANS.inc()
            
            return True
            
        except ApiException as e:
            logger.error(f"Failed to create scan job for '{app_name}': {e}")
            SCAN_JOBS_FAILED.labels(namespace=namespace, application=app_name, reason=str(e.reason)).inc()
            return False
        except Exception as e:
            logger.error(f"Unexpected error creating scan job for '{app_name}': {e}")
            SCAN_JOBS_FAILED.labels(namespace=namespace, application=app_name, reason="unexpected_error").inc()
            return False
    
    def _build_job_spec(self, job_name: str, app_config: Dict, trigger: str) -> Dict:
        """Build Kubernetes Job specification for scanning."""
        return {
            "apiVersion": "batch/v1",
            "kind": "Job",
            "metadata": {
                "name": job_name,
                "namespace": self.namespace,
                "labels": {
                    "app.kubernetes.io/name": "bd-selfscan",
                    "app.kubernetes.io/component": "scanner",
                    "app.kubernetes.io/instance": "bd-selfscan",
                    "scan-type": "automated",
                    "trigger": trigger,
                    "target-application": app_config['name'].lower().replace(' ', '-')
                },
                "annotations": {
                    "bd-selfscan.io/application": app_config['name'],
                    "bd-selfscan.io/namespace": app_config['namespace'],
                    "bd-selfscan.io/trigger": trigger,
                    "bd-selfscan.io/created-by": "bd-selfscan-controller"
                }
            },
            "spec": {
                "backoffLimit": 2,
                "ttlSecondsAfterFinished": 3600,
                "template": {
                    "metadata": {
                        "labels": {
                            "app.kubernetes.io/name": "bd-selfscan",
                            "app.kubernetes.io/component": "scanner",
                            "scan-type": "automated"
                        }
                    },
                    "spec": {
                        "serviceAccountName": "bd-selfscan",
                        "restartPolicy": "Never",
                        "volumes": [
                            {
                                "name": "scripts",
                                "configMap": {
                                    "name": "bd-selfscan-scanner-scripts",
                                    "defaultMode": 0o755
                                }
                            },
                            {
                                "name": "applications-config",
                                "configMap": {
                                    "name": "bd-selfscan-applications"
                                }
                            },
                            {
                                "name": "temp-storage",
                                "emptyDir": {
                                    "sizeLimit": "50Gi"
                                }
                            }
                        ],
                        "initContainers": [
                            {
                                "name": "install-tools",
                                "image": "alpine:3.19",
                                "command": ["/bin/sh", "-c"],
                                "args": [
                                    "apk add --no-cache curl jq bash coreutils openjdk17-jre skopeo yq && "
                                    "curl -fsSL -o /usr/local/bin/kubectl "
                                    "\"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && "
                                    "chmod +x /usr/local/bin/kubectl"
                                ],
                                "volumeMounts": [
                                    {
                                        "name": "temp-storage",
                                        "mountPath": "/tmp"
                                    }
                                ]
                            }
                        ],
                        "containers": [
                            {
                                "name": "scanner",
                                "image": "alpine:3.19",
                                "command": ["/bin/bash"],
                                "args": ["-c", f"/scripts/scan-application.sh '{app_config['name']}'"],
                                "volumeMounts": [
                                    {
                                        "name": "scripts",
                                        "mountPath": "/scripts"
                                    },
                                    {
                                        "name": "applications-config",
                                        "mountPath": "/config"
                                    },
                                    {
                                        "name": "temp-storage",
                                        "mountPath": "/tmp/container-images"
                                    }
                                ],
                                "env": [
                                    {
                                        "name": "BD_URL",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "blackduck-creds",
                                                "key": "url"
                                            }
                                        }
                                    },
                                    {
                                        "name": "BD_TOKEN",
                                        "valueFrom": {
                                            "secretKeyRef": {
                                                "name": "blackduck-creds",
                                                "key": "token"
                                            }
                                        }
                                    },
                                    {
                                        "name": "TRUST_CERT",
                                        "value": "true"
                                    },
                                    {
                                        "name": "SCAN_TRIGGER",
                                        "value": trigger
                                    }
                                ],
                                "resources": {
                                    "requests": {
                                        "memory": "2Gi",
                                        "cpu": "500m"
                                    },
                                    "limits": {
                                        "memory": "8Gi",
                                        "cpu": "4",
                                        "ephemeral-storage": "50Gi"
                                    }
                                }
                            }
                        ]
                    }
                }
            }
        }
    
    def _process_deployment_event(self, event: Dict):
        """Process a deployment event and potentially trigger a scan."""
        event_type = event['type']
        deployment = event['object']
        
        namespace = deployment.metadata.namespace
        name = deployment.metadata.name
        labels = deployment.metadata.labels or {}
        
        logger.debug(f"Processing deployment event: {event_type} {namespace}/{name}")
        
        # Record the event
        DEPLOYMENT_EVENTS.labels(
            namespace=namespace, 
            application=name, 
            event_type=event_type
        ).inc()
        
        # Only process ADDED and MODIFIED events
        if event_type not in ['ADDED', 'MODIFIED']:
            return
        
        # Find matching application configuration
        app_config = self._find_matching_application(namespace, labels)
        if not app_config:
            logger.debug(f"No matching application configuration for {namespace}/{name}")
            return
        
        # Check if this deployment should trigger a scan
        if not app_config.get('scanOnDeploy', False):
            logger.debug(f"Application '{app_config['name']}' not configured for auto-scan")
            return
        
        # For MODIFIED events, check if the image actually changed
        if event_type == 'MODIFIED':
            # This is a simplified check - in production you might want more sophisticated logic
            logger.debug(f"Deployment modified, triggering scan for '{app_config['name']}'")
        
        # Create scan job
        logger.info(f"Triggering scan for application '{app_config['name']}' due to {event_type} event")
        self._create_scan_job(app_config, trigger=f"deployment-{event_type.lower()}")
    
    async def watch_deployments(self):
        """Watch for deployment events across all namespaces."""
        logger.info("Starting deployment event watcher...")
        
        while True:
            try:
                w = watch.Watch()
                stream = w.stream(
                    self.k8s_apps_v1.list_deployment_for_all_namespaces,
                    timeout_seconds=300  # Restart watch every 5 minutes
                )
                
                for event in stream:
                    try:
                        self._process_deployment_event(event)
                    except Exception as e:
                        logger.error(f"Error processing deployment event: {e}")
                        continue
                
            except ApiException as e:
                logger.error(f"Kubernetes API error in deployment watcher: {e}")
                CONTROLLER_HEALTH.set(0)
                await asyncio.sleep(30)  # Wait before retrying
            except Exception as e:
                logger.error(f"Unexpected error in deployment watcher: {e}")
                CONTROLLER_HEALTH.set(0)
                await asyncio.sleep(30)
            
            # Reset health status if we get here (successful iteration)
            CONTROLLER_HEALTH.set(1)
    
    async def cleanup_old_jobs(self):
        """Periodically cleanup old completed scan jobs."""
        logger.info("Starting job cleanup routine...")
        
        while True:
            try:
                await asyncio.sleep(3600)  # Run every hour
                
                # Find old completed jobs
                cutoff_time = datetime.now() - timedelta(hours=24)  # Keep jobs for 24 hours
                
                jobs = self.k8s_batch_v1.list_namespaced_job(
                    namespace=self.namespace,
                    label_selector="app.kubernetes.io/name=bd-selfscan,scan-type=automated"
                )
                
                for job in jobs.items:
                    if job.status.completion_time:
                        completion_time = job.status.completion_time.replace(tzinfo=None)
                        if completion_time < cutoff_time:
                            logger.debug(f"Cleaning up old job: {job.metadata.name}")
                            try:
                                self.k8s_batch_v1.delete_namespaced_job(
                                    name=job.metadata.name,
                                    namespace=self.namespace,
                                    propagation_policy='Background'
                                )
                                ACTIVE_SCANS.dec()
                            except ApiException:
                                pass  # Job might have been deleted already
                
            except Exception as e:
                logger.error(f"Error in job cleanup routine: {e}")
                await asyncio.sleep(300)  # Wait 5 minutes before retrying
    
    async def monitor_scan_jobs(self):
        """Monitor scan job status and update metrics."""
        logger.info("Starting scan job monitor...")
        
        while True:
            try:
                await asyncio.sleep(60)  # Check every minute
                
                # Get current scan jobs
                jobs = self.k8s_batch_v1.list_namespaced_job(
                    namespace=self.namespace,
                    label_selector="app.kubernetes.io/name=bd-selfscan"
                )
                
                active_count = 0
                for job in jobs.items:
                    if not job.status.completion_time and not job.status.failed:
                        active_count += 1
                
                ACTIVE_SCANS.set(active_count)
                
            except Exception as e:
                logger.error(f"Error in job monitor: {e}")
                await asyncio.sleep(300)
    
    async def reload_config(self):
        """Periodically reload application configuration."""
        logger.info("Starting configuration reload routine...")
        
        while True:
            try:
                await asyncio.sleep(600)  # Reload every 10 minutes
                self._load_applications_config()
            except Exception as e:
                logger.error(f"Error reloading configuration: {e}")
                await asyncio.sleep(300)
    
    async def run(self):
        """Main controller loop."""
        logger.info("BD SelfScan Controller starting...")
        
        # Start all async tasks
        tasks = [
            asyncio.create_task(self.watch_deployments()),
            asyncio.create_task(self.cleanup_old_jobs()),
            asyncio.create_task(self.monitor_scan_jobs()),
            asyncio.create_task(self.reload_config())
        ]
        
        try:
            await asyncio.gather(*tasks)
        except KeyboardInterrupt:
            logger.info("Received shutdown signal")
        except Exception as e:
            logger.error(f"Controller error: {e}")
            CONTROLLER_HEALTH.set(0)
            raise
        finally:
            logger.info("BD SelfScan Controller shutting down...")
            for task in tasks:
                task.cancel()

def main():
    """Main entry point."""
    try:
        controller = BDSelfScanController()
        asyncio.run(controller.run())
    except KeyboardInterrupt:
        logger.info("Controller interrupted by user")
    except Exception as e:
        logger.error(f"Controller failed: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()