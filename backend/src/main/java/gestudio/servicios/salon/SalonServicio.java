package gestudio.servicios.salon;

import gestudio.dto.salon.SalonMapper;
import gestudio.dto.salon.request.SalonModificacionRequest;
import gestudio.dto.salon.request.SalonRegistroRequest;
import gestudio.dto.salon.response.SalonResponse;
import gestudio.entidades.Salon;
import gestudio.repositorios.SalonRepositorio;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional
public class SalonServicio {

    private final SalonRepositorio salonRepositorio;
    private final SalonMapper salonMapper;

    public SalonServicio(SalonRepositorio salonRepositorio, SalonMapper salonMapper) {
        this.salonRepositorio = salonRepositorio;
        this.salonMapper = salonMapper;
    }

    /**
     * Crea un nuevo salon.
     */
    public SalonResponse registrarSalon(SalonRegistroRequest request) {
        // Convertimos el request en entidad
        Salon salon = salonMapper.toEntity(request);
        // Guardamos en DB
        Salon guardado = salonRepositorio.save(salon);
        // Retornamos como Response
        return salonMapper.toResponse(guardado);
    }

    /**
     * Obtiene la lista completa de salones.
     */
    @Transactional(readOnly = true)
    public Page<SalonResponse> listarSalones(Pageable pageable) {
        return salonRepositorio.findAll(pageable)
                .map(salonMapper::toResponse);
    }

    /**
     * Obtiene un salon por su ID.
     */
    @Transactional(readOnly = true)
    public SalonResponse obtenerSalonPorId(Long id) {
        Salon salon = salonRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No se encontro el salon con id: " + id));
        return salonMapper.toResponse(salon);
    }

    /**
     * Actualiza un salon existente.
     */
    public SalonResponse actualizarSalon(Long id, SalonModificacionRequest request) {
        // Buscamos el salon
        Salon salon = salonRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No se encontro el salon con id: " + id));
        // Mapeamos los campos modificables
        Salon datosNuevos = salonMapper.toEntity(request);
        // Actualizamos campos en la entidad original
        salon.setNombre(datosNuevos.getNombre());
        salon.setDescripcion(datosNuevos.getDescripcion());
        // Guardamos cambios
        Salon actualizado = salonRepositorio.save(salon);
        return salonMapper.toResponse(actualizado);
    }

    /**
     * Elimina (fisicamente) un salon.
     * Si quisieras una baja logica, deberias tener un atributo "activo" o similar en tu entidad.
     */
    public void eliminarSalon(Long id) {
        if (!salonRepositorio.existsById(id)) {
            throw new IllegalArgumentException("No existe salon con id: " + id);
        }
        salonRepositorio.deleteById(id);
    }
}