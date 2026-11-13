# Instrumentação de Microsserviços com Prometheus

> **Referência histórica de Spring Boot, não aplicável diretamente ao código
> Go/Flask deste projeto.** Não é necessário instalar Java, Maven ou Gradle
> para executar o ToggleMaster. Consulte o
> [guia central, seção 8.4](../../../README.md#84-métricas-da-aplicação-não-estão-prontas-automaticamente)
> para os requisitos reais de endpoints, portas e seletores.

Este guia descreve como adicionar suporte a métricas Prometheus nos microsserviços ToggleMaster.

## Pré-requisitos

- Spring Boot 2.0+
- Maven ou Gradle

## Adição de Dependências

### Maven (pom.xml)

```xml
<!-- Spring Boot Actuator -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>

<!-- Prometheus Registry -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- Opcional: para melhor tracking de requisições HTTP -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-core</artifactId>
</dependency>
```

### Gradle (build.gradle)

```gradle
dependencies {
    // Spring Boot Actuator
    implementation 'org.springframework.boot:spring-boot-starter-actuator'
    
    // Prometheus Registry
    implementation 'io.micrometer:micrometer-registry-prometheus'
    
    // Core metrics
    implementation 'io.micrometer:micrometer-core'
}
```

## Configuração (application.yml / application.properties)

### application.yml

```yaml
management:
  endpoints:
    web:
      exposure:
        include: prometheus,health,metrics,info
  endpoint:
    prometheus:
      enabled: true
    metrics:
      enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
    distribution:
      percentiles-histogram:
        http.server.requests: true
      percentiles:
        http.server.requests: 0.5,0.95,0.99
      slo:
        http.server.requests: 50ms,100ms,500ms,1s
    tags:
      application: ${spring.application.name}
      environment: ${app.environment:development}
```

### application.properties

```properties
management.endpoints.web.exposure.include=prometheus,health,metrics,info
management.endpoint.prometheus.enabled=true
management.endpoint.metrics.enabled=true
management.metrics.export.prometheus.enabled=true
management.metrics.distribution.percentiles-histogram.http.server.requests=true
management.metrics.distribution.percentiles.http.server.requests=0.5,0.95,0.99
management.metrics.distribution.slo.http.server.requests=50ms,100ms,500ms,1s
management.metrics.tags.application=${spring.application.name}
management.metrics.tags.environment=development
```

## Métricas Expostas Automaticamente

Com Micrometer + Prometheus, Spring Boot expõe automaticamente:

### HTTP Metrics
- `http_requests_total` - Total de requisições HTTP
- `http_request_duration_seconds` - Duração das requisições (com histograma)
- `http_requests_active_count` - Requisições ativas no momento

### JVM Metrics
- `jvm_memory_used_bytes` - Memória usada pela JVM
- `jvm_memory_max_bytes` - Memória máxima da JVM
- `jvm_threads_live_threads` - Threads ativas
- `jvm_gc_pause_seconds` - Tempo de pausa do GC

### Database Metrics (HikariCP)
- `hikaricp_connections_active` - Conexões ativas
- `hikaricp_connections_idle` - Conexões idle
- `hikaricp_connections_max` - Conexões máximas

### Custom Metrics

#### Exemplo 1: Counter (contador)

```java
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

@Service
public class ToggleService {
    private final Counter toggleEvaluated;
    
    public ToggleService(MeterRegistry meterRegistry) {
        this.toggleEvaluated = Counter.builder("toggle.evaluated")
            .description("Total de toggles avaliados")
            .tag("service", "flag-service")
            .register(meterRegistry);
    }
    
    public void evaluateToggle(String toggleName) {
        // lógica
        toggleEvaluated.increment();
    }
}
```

#### Exemplo 2: Gauge (medidor)

```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;

@Service
public class CacheService {
    private final AtomicInteger cacheSize = new AtomicInteger(0);
    
    public CacheService(MeterRegistry meterRegistry) {
        Gauge.builder("cache.size", cacheSize, AtomicInteger::get)
            .description("Tamanho do cache")
            .tag("service", "auth-service")
            .register(meterRegistry);
    }
}
```

#### Exemplo 3: Timer (temporizador)

```java
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;

@Service
public class AuthService {
    private final MeterRegistry meterRegistry;
    
    public AuthService(MeterRegistry meterRegistry) {
        this.meterRegistry = meterRegistry;
    }
    
    public String authenticate(String username, String password) {
        return Timer.builder("auth.time")
            .tag("service", "auth-service")
            .description("Tempo de autenticação")
            .publishPercentiles(0.5, 0.95, 0.99)
            .register(meterRegistry)
            .recordCallable(() -> {
                // lógica de autenticação
                return "token";
            });
    }
}
```

## Anotações para Instrumentação Automática

### @Timed

```java
@RestController
@RequestMapping("/api/auth")
public class AuthController {
    
    @PostMapping("/login")
    @Timed(
        value = "auth.login",
        description = "Tempo de requisição de login",
        extraTags = {"service", "auth"}
    )
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        // implementação
    }
}
```

### @CacheEvict com Métricas

```java
@Service
public class UserService {
    
    @Cacheable("users")
    @Timed(value = "user.fetch.time")
    public User getUserById(Long id) {
        // buscar usuário
    }
}
```

## Definição de SLO (Service Level Objectives)

O exemplo abaixo define limites de latência esperados:

```yaml
management:
  metrics:
    distribution:
      slo:
        http.server.requests: 50ms,100ms,500ms,1s,5s
        # Define buckets: <= 50ms, <= 100ms, <= 500ms, <= 1s, <= 5s
```

Isso permite criar alertas baseados em SLO:

```promql
# Percentual de requisições dentro do SLO (< 100ms)
sum(rate(http_request_duration_seconds_bucket{le="0.1"}[5m])) 
/ 
sum(rate(http_request_duration_seconds_count[5m]))
* 100
```

## Endpoint Prometheus

Após inicializar o serviço, as métricas estarão disponíveis em:

```
GET http://localhost:{porta}/actuator/prometheus
```

### Exemplo

```bash
curl http://localhost:8001/actuator/prometheus | head -30

# OUTPUT:
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{application="auth-service",method="POST",status="200"} 42.0
http_requests_total{application="auth-service",method="GET",status="404"} 3.0

# HELP http_request_duration_seconds HTTP request latencies in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{application="auth-service",le="0.05"} 10.0
http_request_duration_seconds_bucket{application="auth-service",le="0.1"} 32.0
http_request_duration_seconds_bucket{application="auth-service",le="0.5"} 40.0
```

## Verificação de Métricas no Prometheus

Após configurar o ServiceMonitor, as métricas aparecerão no Prometheus:

```bash
# Port-forward para Prometheus
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090

# Abrir http://localhost:9090
```

### Queries para verificar:

1. **Requisições por serviço**:
   ```promql
   http_requests_total{application=~"auth-service|flag-service|targeting-service"}
   ```

2. **Taxa de erro por serviço**:
   ```promql
   rate(http_requests_total{status=~"5.."}[5m]) by (application)
   ```

3. **P95 Latência**:
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) by (application)
   ```

4. **Uso de memória JVM**:
   ```promql
   jvm_memory_used_bytes{application="auth-service"}
   ```

## Boas Práticas

### ✅ DO's (Faça)

1. **Use nomes descritivos para métricas**
   ```java
   // ✅ Bom
   Counter.builder("toggle.evaluation.success")
   
   // ❌ Ruim
   Counter.builder("count1")
   ```

2. **Adicione tags relevantes**
   ```java
   // ✅ Bom
   .tag("service", "flag-service")
   .tag("operation", "evaluate")
   
   // ❌ Ruim
   // sem tags
   ```

3. **Use unidades padrão**
   ```java
   // ✅ Bom: segundos para duração
   .baseTimeUnit(TimeUnit.SECONDS)
   
   // ❌ Ruim: milissegundos sem conversão
   ```

4. **Evite cardinalidade alta**
   ```java
   // ✅ Bom: tags fixas
   .tag("status", "success")
   
   // ❌ Ruim: values dinâmicos
   .tag("user_id", userId)  // milhões de valores diferentes
   ```

### ❌ DON'Ts (Não faça)

1. **Não incremente contadores em loops críticos**
   ```java
   // ❌ Ruim: overhead de performance
   for (Item item : items) {
       counter.increment();
   }
   
   // ✅ Bom: incrementar uma vez
   counter.increment(items.size());
   ```

2. **Não use string interpolation em nomes de métricas**
   ```java
   // ❌ Ruim
   Counter.builder("user_" + userId + "_requests")
   
   // ✅ Bom
   Counter.builder("user.requests")
       .tag("user_id", userId)
   ```

3. **Não exponha dados sensíveis**
   ```java
   // ❌ Ruim: expõe senhas/tokens
   .tag("password", request.getPassword())
   
   // ✅ Bom: métricas seguras
   .tag("auth_type", "password")
   ```

## Troubleshooting

### Métricas não aparecem em /actuator/prometheus

**Verificar**:
1. Dependência `micrometer-registry-prometheus` está no classpath?
2. Endpoint está exposto em `management.endpoints.web.exposure.include`?
3. Serviço iniciou sem erros?

```bash
# Verificar logs
kubectl logs <pod> -n <namespace> | grep -i prometheus
```

### ServiceMonitor não encontra o endpoint

**Verificar**:
1. Service tem porta com nome "http"?
   ```yaml
   spec:
     ports:
       - name: http  # ← importante
         port: 8001
   ```

2. ServiceMonitor tem seletor correto?
   ```yaml
   spec:
     selector:
       matchLabels:
         app: auth  # ← deve corresponder ao label do Service
   ```

3. Testar conectividade manual:
   ```bash
   kubectl exec -it <prometheus-pod> -n monitoring -- \
     curl http://<service-name>.<namespace>:<port>/actuator/prometheus
   ```

## Referências

- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [Micrometer Prometheus](https://micrometer.io/docs/registry/prometheus)
- [Prometheus Java Client](https://github.com/prometheus/client_java)
- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
