using System;
using System.Web;

namespace DBProject
{
    /// <summary>
    /// HTTP Handler that provides a health check endpoint for container liveness/readiness probes.
    /// Accessible at GET /health
    /// </summary>
    public class HealthCheckHandler : IHttpHandler
    {
        public bool IsReusable => true;

        public void ProcessRequest(HttpContext context)
        {
            context.Response.ContentType = "application/json";
            context.Response.StatusCode = 200;
            context.Response.Write("{\"status\":\"healthy\",\"application\":\"HospitalManagement\",\"timestamp\":\"" + DateTime.UtcNow.ToString("o") + "\"}");
        }
    }
}
