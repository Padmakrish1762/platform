-- AlterTable
ALTER TABLE "oidc_issuer" ADD COLUMN     "ecosystemId" UUID;

-- AddForeignKey
ALTER TABLE "oidc_issuer" ADD CONSTRAINT "oidc_issuer_ecosystemId_fkey" FOREIGN KEY ("ecosystemId") REFERENCES "ecosystem"("id") ON DELETE SET NULL ON UPDATE CASCADE;
