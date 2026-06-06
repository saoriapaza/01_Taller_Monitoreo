package com.cinema.ticketsales;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/")
public class TicketController {

    private final WebClient webClient;
    private final List<Ticket> ticketDatabase = new ArrayList<>();
    
    private final Counter ticketSuccessCounter;
    private final Counter ticketFailureCounter;
    private final Counter ticketTimeoutCounter;
    private final io.micrometer.core.instrument.Timer ticketProcessTimer;

    public TicketController(WebClient.Builder webClientBuilder, 
                            @Value("${movie.catalog.url}") String movieCatalogUrl,
                            MeterRegistry registry) {
        this.webClient = webClientBuilder.baseUrl(movieCatalogUrl).build();
        
        this.ticketSuccessCounter = Counter.builder("tickets.sales.success")
                .description("Number of successful ticket sales")
                .register(registry);
                
        this.ticketFailureCounter = Counter.builder("tickets.sales.failure")
                .description("Number of failed ticket sales due to logic or downstream errors")
                .register(registry);
                
        this.ticketTimeoutCounter = Counter.builder("tickets.sales.timeout")
                .description("Number of ticket sales that failed due to timeout")
                .register(registry);

        this.ticketProcessTimer = io.micrometer.core.instrument.Timer.builder("tickets.process.time")
                .description("Time taken to process ticket actions")
                .register(registry);
    }

    @GetMapping("/health")
    public ResponseEntity<String> healthCheck() {
        return ResponseEntity.ok("Ticket Sales Service is UP");
    }

    @GetMapping("/tickets")
    public ResponseEntity<List<Ticket>> getAllTickets() {
        return ResponseEntity.ok(ticketDatabase);
    }

    @PostMapping("/tickets/buy")
    public Mono<ResponseEntity<String>> buyTicket(@RequestParam String movieId) {
        // We call Service A to reserve the seat.
        // We set a strict timeout of 2 seconds.
        return webClient.post()
                .uri("/movies/{id}/reserve", movieId)
                .retrieve()
                .bodyToMono(String.class)
                .timeout(Duration.ofSeconds(2)) // Strict timeout for Casuistica 2
                .map(response -> {
                    // Success
                    Ticket ticket = new Ticket(UUID.randomUUID().toString(), movieId, "CONFIRMED");
                    ticketDatabase.add(ticket);
                    ticketSuccessCounter.increment();
                    return ResponseEntity.ok("Ticket purchased successfully. ID: " + ticket.getId());
                })
                .onErrorResume(e -> {
                    // Handle Errors
                    if (e instanceof java.util.concurrent.TimeoutException) {
                        ticketTimeoutCounter.increment();
                        return Mono.just(ResponseEntity.status(HttpStatus.GATEWAY_TIMEOUT)
                                .body("Error: Service A is taking too long to respond (Timeout)."));
                    } else if (e instanceof WebClientResponseException) {
                        ticketFailureCounter.increment();
                        WebClientResponseException webEx = (WebClientResponseException) e;
                        return Mono.just(ResponseEntity.status(webEx.getStatusCode())
                                .body("Error from Service A: " + webEx.getResponseBodyAsString()));
                    } else {
                        ticketFailureCounter.increment();
                        return Mono.just(ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                                .body("Unexpected error: " + e.getMessage()));
                    }
                });
    }

    @GetMapping("/tickets/{id}")
    public ResponseEntity<Ticket> getTicket(@PathVariable String id) {
        long start = System.currentTimeMillis();
        try {
            return ticketDatabase.stream()
                    .filter(t -> t.getId().equals(id))
                    .findFirst()
                    .map(ResponseEntity::ok)
                    .orElse(ResponseEntity.notFound().build());
        } finally {
            ticketProcessTimer.record(System.currentTimeMillis() - start, java.util.concurrent.TimeUnit.MILLISECONDS);
        }
    }

    @DeleteMapping("/tickets/{id}")
    public ResponseEntity<String> cancelTicket(@PathVariable String id) {
        long start = System.currentTimeMillis();
        try {
            boolean removed = ticketDatabase.removeIf(t -> t.getId().equals(id));
            if (removed) {
                return ResponseEntity.ok("Ticket canceled successfully");
            } else {
                return ResponseEntity.notFound().build();
            }
        } finally {
            ticketProcessTimer.record(System.currentTimeMillis() - start, java.util.concurrent.TimeUnit.MILLISECONDS);
        }
    }

    // Inner class for mock data
    static class Ticket {
        private String id;
        private String movieId;
        private String status;

        public Ticket(String id, String movieId, String status) {
            this.id = id;
            this.movieId = movieId;
            this.status = status;
        }

        public String getId() { return id; }
        public String getMovieId() { return movieId; }
        public String getStatus() { return status; }
    }
}
