package gestudio.dto;

import org.springframework.data.domain.Page;

import java.util.List;

public record PageResponse<T>(
        List<T> content,
        long totalElements,
        long totalPages,
        int size,
        int number,
        boolean first,
        boolean last
) {
    public static <T> PageResponse<T> from(Page<T> page) {
        long totalPages = page.getSize() == 0 ? 0 : Math.ceilDiv(page.getTotalElements(), page.getSize());
        return new PageResponse<>(page.getContent(), page.getTotalElements(), totalPages,
                page.getSize(), page.getNumber(), page.isFirst(), page.isLast());
    }
}
