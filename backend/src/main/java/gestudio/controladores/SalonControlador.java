package gestudio.controladores;

import gestudio.dto.PageResponse;
import gestudio.dto.salon.request.SalonModificacionRequest;
import gestudio.dto.salon.request.SalonRegistroRequest;
import gestudio.dto.salon.response.SalonResponse;
import gestudio.servicios.salon.SalonServicio;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/salones")
public class SalonControlador {

    private final SalonServicio salonServicio;

    public SalonControlador(SalonServicio salonServicio) {
        this.salonServicio = salonServicio;
    }

    @PostMapping
    public ResponseEntity<SalonResponse> registrarSalon(@Valid @RequestBody SalonRegistroRequest request) {
        SalonResponse salon = salonServicio.registrarSalon(request);
        return new ResponseEntity<>(salon, HttpStatus.CREATED);
    }

    @GetMapping
    public ResponseEntity<PageResponse<SalonResponse>> listarSalones(Pageable pageable) {
        return ResponseEntity.ok(PageResponse.from(salonServicio.listarSalones(pageable)));
    }

    @GetMapping("/{id}")
    public ResponseEntity<SalonResponse> obtenerSalonPorId(@PathVariable Long id) {
        SalonResponse salon = salonServicio.obtenerSalonPorId(id);
        return ResponseEntity.ok(salon);
    }

    @PutMapping("/{id}")
    public ResponseEntity<SalonResponse> actualizarSalon(@PathVariable Long id, @Valid @RequestBody SalonModificacionRequest request) {
        SalonResponse salon = salonServicio.actualizarSalon(id, request);
        return ResponseEntity.ok(salon);
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> eliminarSalon(@PathVariable Long id) {
        salonServicio.eliminarSalon(id);
        return ResponseEntity.noContent().build();
    }
}
