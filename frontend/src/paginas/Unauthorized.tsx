import React from "react";
import { useNavigate } from "react-router";

const Unauthorized: React.FC = () => {
    const navigate = useNavigate();

    return (
        <div className="unauthorized-container" style={{ textAlign: "center", padding: "2rem" }}>
            <h1>Acceso no autorizado</h1>
            <p>No tienes permisos para acceder a esta página.</p>
            <button onClick={() => navigate("/")} className="btn btn-primary">
                Volver al inicio
            </button>
        </div>
    );
};

export default Unauthorized;
