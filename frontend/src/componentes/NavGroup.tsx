import React from "react";
import { Link, useLocation } from "react-router-dom";
import { ChevronDown } from "lucide-react";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "../componentes/ui/collapsible";
import { cn } from "../lib/utils";
import type { NavigationItem } from "../config/navigation";

interface NavGroupProps {
  item: NavigationItem;
  isExpanded: boolean;
}

const NavGroup: React.FC<NavGroupProps> = ({ item, isExpanded }) => {
  const location = useLocation();
  const pathIsActive = (href?: string) => Boolean(href && (location.pathname === href || location.pathname.startsWith(`${href}/`)));
  const isActive = pathIsActive(item.href);
  const hasActiveChild = item.items?.some((subItem) => pathIsActive(subItem.href)) ?? false;
  const Icon = item.icon;

  if (!item.items || item.items.length === 0) {
    return (
      <Link
        to={item.href || "#"}
        className={cn(
          "nav-item",
          isActive
            ? "nav-item-active"
            : ""
        )}
        title={isExpanded ? undefined : item.label}
      >
        {Icon && <Icon className="w-5 h-5 shrink-0" />}
        {isExpanded && <span>{item.label}</span>}
      </Link>
    );
  }

  return (
    <Collapsible className="w-full" defaultOpen={hasActiveChild}>
      <CollapsibleTrigger className={cn("group nav-item justify-between", hasActiveChild && "text-foreground")} title={isExpanded ? undefined : item.label}>
        <div className="flex min-w-0 items-center gap-3">
          {Icon && <Icon className="size-5 shrink-0" />}
          {isExpanded && <span className="truncate">{item.label}</span>}
        </div>
        {isExpanded && <ChevronDown className="size-4 shrink-0 text-muted-foreground transition-transform group-data-[state=open]:rotate-180" />}
      </CollapsibleTrigger>
      {isExpanded && <CollapsibleContent className="space-y-1 pt-1">
        {item.items.map((subItem) => {
          const SubIcon = subItem.icon;
          const subItemActive = pathIsActive(subItem.href);
          return (
            <Link
              key={subItem.id}
              to={subItem.href || "#"}
              className={cn("nav-item nav-subitem", subItemActive && "nav-item-active")}
            >
              {SubIcon && <SubIcon className="size-4 shrink-0" />}
              <span className="truncate">{subItem.label}</span>
            </Link>
          );
        })}
      </CollapsibleContent>}
    </Collapsible>
  );
};

export default NavGroup;
