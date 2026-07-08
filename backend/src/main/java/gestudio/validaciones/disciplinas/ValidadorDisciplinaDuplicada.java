//package gestudio.validaciones.disciplinas;
//
//import gestudio.dto.disciplina.request.DisciplinaRegistroRequest;
//import gestudio.repositorios.DisciplinaRepositorio;
//import gestudio.validaciones.Validador;
//import org.springframework.stereotype.Component;
//
//@Component
//public class ValidadorDisciplinaDuplicada implements Validador<DisciplinaRegistroRequest> {
//
//    private final DisciplinaRepositorio disciplinaRepositorio;
//
//    public ValidadorDisciplinaDuplicada(DisciplinaRepositorio disciplinaRepositorio) {
//        this.disciplinaRepositorio = disciplinaRepositorio;
//    }
//
//    @Override
//    public void validar(DisciplinaRegistroRequest datos) {
//        if (disciplinaRepositorio.existsByNombreAndHorarioInicio(datos.nombre(), datos.horarioInicio())) {
//            throw new RuntimeException("La disciplina ya esta registrada con el mismo nombre y horario: "
//                    + datos.nombre());
//        }
//    }
//}
