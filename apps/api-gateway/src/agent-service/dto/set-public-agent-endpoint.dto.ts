import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsString } from 'class-validator';

import { Transform } from 'class-transformer';
import { trim } from '@credebl/common/cast.helper';

export class SetPublicAgentEndpointDto {
  @ApiPropertyOptional()
  @Transform(({ value }) => trim(value))
  @IsNotEmpty({ message: 'Public endpoint is required.' })
  @IsString({ message: 'Public endpoint must be in string format.' })
  publicEndpoint: string;
}
