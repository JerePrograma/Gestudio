import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import Boton from "../../componentes/comunes/Boton";
import recargosApi from "../../api/recargosApi";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import { toast } from "react-toastify";
import PermissionGate from "../../componentes/comunes/PermissionGate";
import { PERMISSIONS } from "../../config/permissions";

interface Recargo {
    id: number;
    descripcion: string;
}

const Recargos = () => {
    const [recargos, setRecargos] = useState<Recargo[]>([]);
    const [loading, setLoading] = useState(false);
    const navigate = useNavigate();

    const fetchRecargos = useCallback(async () => {
        try {
            setLoading(true);
            const response = await recargosApi.listarRecargos();
            setRecargos(response);
        } catch {
            toast.error("Error al cargar los recargos:");
        } finally {
            setLoading(false);
        }
    }, []);

    useEffect(() => {
        fetchRecargos();
    }, [fetchRecargos]);

    if (loading) return <div className="text-center py-4">Cargando...</div>;

    return (
        <div className="page-container">
            <h1 className="page-title">Recargos</h1>
            <div className="page-button-group flex justify-end mb-4">
                <PermissionGate permission={PERMISSIONS.CONFIG_ADMIN}>
                    <Boton onClick={() => navigate("/recargos/formulario")} className="page-button">
                        <PlusCircle className="w-5 h-5 mr-2" />
                        Nuevo Recargo
                    </Boton>
                </PermissionGate>
            </div>
            <div className="page-card">
                <Tabla
                    headers={["ID", "Descripcion", "Acciones"]}
                    data={recargos}
                    getRowKey={(row) => row.id}
                    actions={(fila) => (
                        <PermissionGate permission={PERMISSIONS.CONFIG_ADMIN}>
                            <div className="flex gap-2">
                                <Boton
                                    onClick={() => navigate(`/recargos/formulario?id=${fila.id}`)}
                                    className="page-button-secondary"
                                >
                                    <Pencil className="w-4 h-4 mr-2" />
                                    Editar
                                </Boton>
                                <Boton className="page-button-danger">
                                    <Trash2 className="w-4 h-4 mr-2" />
                                    Eliminar
                                </Boton>
                            </div>
                        </PermissionGate>
                    )}
                    customRender={(fila) => [fila.id, fila.descripcion]}
                />
            </div>
        </div>
    );
};

export default Recargos;
