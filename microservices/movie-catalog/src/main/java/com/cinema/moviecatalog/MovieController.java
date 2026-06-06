package com.cinema.moviecatalog;

import io.micrometer.core.annotation.Timed;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

@RestController
@RequestMapping("/")
public class MovieController {

    private final Map<String, Movie> movieDatabase = new HashMap<>();
    private final AtomicInteger totalAvailableSeats = new AtomicInteger(0);

    // Metrics
    private final Counter movieSearchesCounter;
    private final Timer reservationTimer;

    public MovieController(MeterRegistry registry) {
        // Initialize mock data
        movieDatabase.put("1", new Movie("1", "Inception", 50));
        movieDatabase.put("2", new Movie("2", "Interstellar", 30));
        movieDatabase.put("3", new Movie("3", "The Dark Knight", 0)); // Sold out example

        updateTotalSeats();

        // Initialize metrics
        this.movieSearchesCounter = Counter.builder("movies.search.count")
                .description("Number of times movies were searched")
                .register(registry);

        this.reservationTimer = Timer.builder("movies.reservation.time")
                .description("Time taken to process a reservation")
                .register(registry);

        Gauge.builder("movies.seats.available", totalAvailableSeats, AtomicInteger::get)
                .description("Total available seats across all movies")
                .register(registry);
                
        // Metric for casuistica 2: expose the delay
        Gauge.builder("movies.artificial.delay", this, MovieController::getArtificialDelay)
                .description("Artificial delay injected via env variable")
                .register(registry);
    }

    private void updateTotalSeats() {
        int seats = movieDatabase.values().stream().mapToInt(Movie::getAvailableSeats).sum();
        totalAvailableSeats.set(seats);
    }

    private double getArtificialDelay() {
        String delayEnv = System.getenv("DELAY_MS");
        if (delayEnv != null && !delayEnv.isEmpty()) {
            try {
                return Double.parseDouble(delayEnv);
            } catch (NumberFormatException e) {
                return 0.0;
            }
        }
        return 0.0;
    }

    private void simulateDelay() {
        double delay = getArtificialDelay();
        if (delay > 0) {
            try {
                Thread.sleep((long) delay);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    @GetMapping("/health")
    public ResponseEntity<String> healthCheck() {
        return ResponseEntity.ok("Movie Catalog Service is UP");
    }

    @GetMapping("/movies")
    public ResponseEntity<List<Movie>> getAllMovies() {
        movieSearchesCounter.increment();
        simulateDelay();
        return ResponseEntity.ok(new ArrayList<>(movieDatabase.values()));
    }

    @GetMapping("/movies/{id}")
    public ResponseEntity<Movie> getMovie(@PathVariable String id) {
        movieSearchesCounter.increment();
        simulateDelay();
        Movie movie = movieDatabase.get(id);
        if (movie != null) {
            return ResponseEntity.ok(movie);
        } else {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping("/movies/{id}/reserve")
    public ResponseEntity<String> reserveSeat(@PathVariable String id) {
        long start = System.currentTimeMillis();
        simulateDelay();
        
        try {
            Movie movie = movieDatabase.get(id);
            if (movie == null) {
                return ResponseEntity.notFound().build();
            }
            if (movie.getAvailableSeats() > 0) {
                movie.setAvailableSeats(movie.getAvailableSeats() - 1);
                updateTotalSeats();
                return ResponseEntity.ok("Reservation successful for " + movie.getTitle());
            } else {
                return ResponseEntity.badRequest().body("Sold out");
            }
        } finally {
            reservationTimer.record(System.currentTimeMillis() - start, TimeUnit.MILLISECONDS);
        }
    }

    @PostMapping("/movies")
    public ResponseEntity<Movie> addMovie(@RequestBody Movie movie) {
        movieSearchesCounter.increment();
        movieDatabase.put(movie.getId(), movie);
        updateTotalSeats();
        return ResponseEntity.status(201).body(movie);
    }

    // Inner class for mock data
    static class Movie {
        private String id;
        private String title;
        private int availableSeats;

        public Movie(String id, String title, int availableSeats) {
            this.id = id;
            this.title = title;
            this.availableSeats = availableSeats;
        }

        public String getId() { return id; }
        public String getTitle() { return title; }
        public int getAvailableSeats() { return availableSeats; }
        public void setAvailableSeats(int availableSeats) { this.availableSeats = availableSeats; }
    }
}
