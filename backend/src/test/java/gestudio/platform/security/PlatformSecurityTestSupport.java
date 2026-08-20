package gestudio.platform.security;

import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.TransactionStatus;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.when;

final class PlatformSecurityTestSupport {
    private PlatformSecurityTestSupport() {
    }

    static PlatformTransactionManager transactionManager() {
        PlatformTransactionManager manager = mock(PlatformTransactionManager.class);
        TransactionStatus status = mock(TransactionStatus.class);
        lenient().when(manager.getTransaction(any(TransactionDefinition.class))).thenReturn(status);
        return manager;
    }
}
