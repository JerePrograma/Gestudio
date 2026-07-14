import {
  BarChart3,
  Building2,
  CalendarCheck,
  CreditCard,
  DollarSign,
  DoorOpen,
  Mic2,
  Package,
  Percent,
  PiggyBank,
  Receipt,
  Shield,
  Tags,
  TrendingUp,
  User,
  UserCheck,
  UserCog,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { PERMISSIONS, type PermissionCode } from "./permissions";

export interface NavigationItem {
  id: string;
  icon?: LucideIcon;
  label: string;
  href?: string;
  description?: string;
  requiredPermissions?: readonly PermissionCode[];
  items?: NavigationItem[];
}

export const filterNavigationItems = (
  items: NavigationItem[],
  hasPermission: (permission: PermissionCode) => boolean,
): NavigationItem[] => items
  .filter((item) => !item.requiredPermissions || item.requiredPermissions.every(hasPermission))
  .map((item) => ({
    ...item,
    items: item.items ? filterNavigationItems(item.items, hasPermission) : undefined,
  }))
  .filter((item) => item.href || (item.items?.length ?? 0) > 0);

export const navigationItems: NavigationItem[] = [
  {
    id: "alumnos",
    icon: User,
    label: "Alumnos",
    href: "/alumnos",
    requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.ALUMNOS_LEER],
  },
  {
    id: "cobranza",
    icon: DollarSign,
    label: "Cobranza",
    href: "/pagos/formulario",
    requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_REGISTRAR],
  },
  {
    id: "pagos",
    icon: Receipt,
    label: "Pagos",
    href: "/pagos",
    requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_LEER],
  },
  {
    id: "caja",
    icon: PiggyBank,
    label: "Caja",
    href: "/caja",
    requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CAJA_LEER],
  },
  {
    id: "administracion",
    label: "Administración",
    icon: Building2,
    items: [
      {
        id: "egresos",
        label: "Egresos",
        href: "/egresos",
        icon: Wallet,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.EGRESOS_ADMIN],
      },
      {
        id: "metodos-pago",
        label: "Métodos de pago",
        href: "/metodos-pago",
        icon: CreditCard,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
      },
      {
        id: "conceptos",
        label: "Conceptos",
        href: "/conceptos",
        icon: Tags,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
      },
      {
        id: "stocks",
        label: "Stock",
        href: "/stocks",
        icon: Package,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.STOCK_LEER],
      },
    ],
  },
  {
    id: "academico",
    label: "Gestión académica",
    icon: CalendarCheck,
    items: [
      {
        id: "inscripciones",
        label: "Inscripciones",
        href: "/inscripciones",
        icon: CalendarCheck,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.INSCRIPCIONES_LEER],
      },
      {
        id: "asistencias",
        label: "Asistencias",
        href: "/asistencias/alumnos",
        icon: CalendarCheck,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.ASISTENCIAS_LEER],
      },
      {
        id: "profesores",
        label: "Profesores",
        href: "/profesores",
        icon: UserCheck,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.PROFESORES_LEER],
      },
      {
        id: "disciplinas",
        label: "Disciplinas",
        href: "/disciplinas",
        icon: Mic2,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.DISCIPLINAS_LEER],
      },
      {
        id: "salones",
        label: "Salones",
        href: "/salones",
        icon: DoorOpen,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
      },
      {
        id: "bonificaciones",
        label: "Bonificaciones",
        href: "/bonificaciones",
        icon: Percent,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
      },
      {
        id: "recargos",
        label: "Recargos",
        href: "/recargos",
        icon: TrendingUp,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
      },
    ],
  },
  {
    id: "reportes",
    label: "Alumnos por disciplina",
    href: "/alumnos-por-disciplina",
    icon: BarChart3,
    requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.REPORTES_LEER, PERMISSIONS.DISCIPLINAS_LEER],
  },
  {
    id: "seguridad",
    label: "Seguridad",
    icon: Shield,
    items: [
      {
        id: "usuarios",
        label: "Usuarios",
        href: "/usuarios",
        icon: UserCog,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.USUARIOS_ADMIN],
      },
      {
        id: "roles",
        label: "Roles",
        href: "/roles",
        icon: Shield,
        requiredPermissions: [PERMISSIONS.APP_ACCESS, PERMISSIONS.ROLES_ADMIN],
      },
    ],
  },
];
