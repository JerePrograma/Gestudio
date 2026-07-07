import type React from "react";
import { Link } from "react-router-dom";
import { navigationItems, type NavigationItem } from "../config/navigation";
import { ChevronDown, ExternalLink } from "lucide-react";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "../componentes/ui/card";
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from "../componentes/ui/collapsible";
import { Button } from "../componentes/ui/button";
import { ScrollArea } from "../componentes/ui/scroll-area";
import { cn } from "../lib/utils";
import { useAuth } from "../hooks/context/useAuth";
import PageHeader from "../componentes/comunes/PageHeader";

// Función utilitaria para filtrar los ítems de navegación de forma inmutable.
const filterNavigationItems = (
  items: NavigationItem[],
  hasRole: (role: string) => boolean
): NavigationItem[] => {
  return items
    .filter((item) => !item.requiredRole || hasRole(item.requiredRole))
    .map((item) => ({
      ...item,
      items: item.items
        ? filterNavigationItems(item.items, hasRole)
        : undefined,
    }));
};

const SingleCard: React.FC<{ item: NavigationItem }> = ({ item }) => {
  const Icon = item.icon;
  return (
    <Link to={item.href ?? "#"} className="block h-full">
      <Card className="group h-full transition-colors hover:border-primary/35 hover:shadow-md">
        <CardHeader>
          <div className="flex items-center space-x-4">
            {Icon && (
              <div className="rounded-xl bg-primary/10 p-3 transition-colors group-hover:bg-primary/20">
                <Icon className="size-6 text-primary" />
              </div>
            )}
            <CardTitle className="line-clamp-2">{item.label}</CardTitle>
          </div>
        </CardHeader>
        <CardContent>
          <div className="flex items-center text-sm font-semibold text-primary">
            Acceder
            <ExternalLink className="ml-1 h-4 w-4 transition-transform group-hover:translate-x-1" />
          </div>
        </CardContent>
      </Card>
    </Link>
  );
};

interface CategoryCardProps {
  item: NavigationItem;
}

const CategoryCard: React.FC<CategoryCardProps> = ({ item }) => {
  const Icon = item.icon;
  const subItems = item.items || [];
  return (
    <Card className="overflow-hidden h-full">
      <Collapsible>
        <CollapsibleTrigger className="w-full">
          <CardHeader className="group cursor-pointer hover:bg-muted/50">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4">
                {Icon && (
                  <div className="rounded-xl bg-primary/10 p-3">
                    <Icon className="h-6 w-6 text-primary" />
                  </div>
                )}
                <div className="text-left">
                  <CardTitle className="line-clamp-2">{item.label}</CardTitle>
                  {item.description && (
                    <CardDescription className="line-clamp-2">
                      {item.description}
                    </CardDescription>
                  )}
                </div>
              </div>
              <ChevronDown className="h-5 w-5 shrink-0 text-muted-foreground transition-transform duration-200 group-data-[state=open]:rotate-180" />
            </div>
          </CardHeader>
        </CollapsibleTrigger>
        <CollapsibleContent className="pl-4">
          <CardContent className="grid gap-4 p-6 pt-0">
            <ScrollArea className="max-h-[300px]">
              {subItems.map((subItem) => (
                <Link key={subItem.id} to={subItem.href ?? "#"}>
                  <Button
                    variant="ghost"
                    className={cn(
                      "w-full justify-start gap-2 font-normal",
                      "hover:bg-muted hover:text-primary"
                    )}
                  >
                    {subItem.icon && (
                      <subItem.icon className="h-4 w-4 shrink-0" />
                    )}
                    <span className="truncate">{subItem.label}</span>
                  </Button>
                </Link>
              ))}
            </ScrollArea>
          </CardContent>
        </CollapsibleContent>
      </Collapsible>
    </Card>
  );
};

const Dashboard: React.FC = () => {
  const { hasRole } = useAuth();

  // Utilizamos la función utilitaria para filtrar los ítems sin mutar el array original.
  const filteredNavigation = filterNavigationItems(navigationItems, hasRole);

  // Separamos los ítems en categorías (con sub-items) y accesos directos (sin sub-items)
  const categories = filteredNavigation.filter(
    (item) => item.items && item.items.length > 0
  );
  const singleItems = filteredNavigation.filter(
    (item) => !item.items || item.items.length === 0
  );

  return (
    <div className="page-container">
      <PageHeader eyebrow="LE DANCE" title="Panel de control" description="Accesos rápidos a la operación diaria y la administración del sistema." />
      {/* Accesos Directos */}
      {singleItems.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-xl font-semibold tracking-tight">
            Accesos frecuentes
          </h2>
          <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
            {singleItems.map((item) => (
              <SingleCard key={item.id} item={item} />
            ))}
          </div>
        </section>
      )}
      {/* Categorías */}
      <section className="space-y-4">
        <h2 className="text-xl font-semibold tracking-tight">
          Gestión del sistema
        </h2>
        <div className="grid gap-4 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-3 2xl:grid-cols-4">
          {categories.map((category) => (
            <CategoryCard key={category.id} item={category} />
          ))}
        </div>
      </section>
    </div>
  );
};

Dashboard.displayName = "Dashboard";

export default Dashboard;
