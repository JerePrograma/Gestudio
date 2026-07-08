// src/main/java/gestudio/servicios/pago/MetodoPagoServicio.java
package gestudio.servicios.pago;

import gestudio.dto.metodopago.MetodoPagoMapper;
import gestudio.dto.metodopago.request.MetodoPagoRegistroRequest;
import gestudio.dto.metodopago.response.MetodoPagoResponse;
import gestudio.entidades.MetodoPago;
import gestudio.repositorios.MetodoPagoRepositorio;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class MetodoPagoServicio {

    private final MetodoPagoRepositorio metodoPagoRepositorio;
    private final MetodoPagoMapper metodoPagoMapper;

    public MetodoPagoServicio(MetodoPagoRepositorio metodoPagoRepositorio,
                              MetodoPagoMapper metodoPagoMapper) {
        this.metodoPagoRepositorio = metodoPagoRepositorio;
        this.metodoPagoMapper = metodoPagoMapper;
    }

    /**
     * Crea un nuevo metodo de pago.
     */
    public MetodoPagoResponse registrar(MetodoPagoRegistroRequest request) {
        MetodoPago nuevo = metodoPagoMapper.toEntity(request);
        nuevo.setActivo(true);
        MetodoPago guardado = metodoPagoRepositorio.save(nuevo);
        return metodoPagoMapper.toDTO(guardado);
    }

    /**
     * Lista todos los metodos de pago.
     */
    @Transactional(readOnly = true)
    public List<MetodoPagoResponse> listar() {
        return metodoPagoRepositorio.findAll().stream()
                .map(metodoPagoMapper::toDTO)
                .toList();
    }

    /**
     * Obtiene un metodo de pago por su ID.
     */
    @Transactional(readOnly = true)
    public MetodoPagoResponse obtenerPorId(Long id) {
        MetodoPago metodo = metodoPagoRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No se encontro el metodo de pago con ID: " + id));
        return metodoPagoMapper.toDTO(metodo);
    }

    /**
     * Actualiza un metodo de pago existente.
     */
    public MetodoPagoResponse actualizar(Long id, MetodoPagoRegistroRequest request) {
        MetodoPago metodo = metodoPagoRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No se encontro el metodo de pago con ID: " + id));
        metodoPagoMapper.updateEntityFromRequest(request, metodo);
        MetodoPago actualizado = metodoPagoRepositorio.save(metodo);
        return metodoPagoMapper.toDTO(actualizado);
    }

    /**
     * Realiza la baja logica de un metodo de pago.
     */
    public void eliminar(Long id) {
        metodoPagoRepositorio.deleteById(id);
    }

    /**
     * Realiza la baja logica de un metodo de pago.
     */
    public void darBaja(Long id) {
        MetodoPago metodo = metodoPagoRepositorio.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("No se encontro el metodo de pago con ID: " + id));
        metodo.setActivo(false);
        metodoPagoRepositorio.save(metodo);
    }
}
